//! H264 on an AMD or Intel GPU through FFmpeg's VAAPI encoder, on Linux.
//!
//! LiveKit has a VAAPI encoder of its own, but on AMD (RX 9070 XT, Mesa 26.2,
//! Oct 9 2026) it stalled the viewer for seconds at a time and made 34 of 60
//! pictures a second, where FFmpeg's `h264_vaapi` on the same GPU was clean.
//! FFmpeg cannot be linked into this crate beside libwebrtc, which carries
//! Chromium's FFmpeg under the same symbol names, so it lives in a library of
//! its own (`native/ffenc`), opened at run time. FFmpeg's encoder sends the
//! bitrate to the GPU only on a keyframe, so the build patches it to send a
//! moved rate with the next picture (`third_party/ffmpeg/RIFT_PATCHES.md`).
use super::h264::{self, ParameterSets};
use super::worker::{self, Session, SharedSink, GOP_SECONDS};
use super::{Encoded, EncoderSettings, GpuCodec, Nv12Frame};
use libloading::Library;
use std::ffi::{c_char, c_void, CStr, CString};
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, OnceLock};

/// The library's interface version this crate was written against
/// (`RIFT_FFENC_ABI` in `ffenc.h`).
const ABI: i32 = 1;

/// The library's name, in the bundle's `lib` folder.
const LIBRARY: &str = "librift_ffenc.so";

/// What a test or bench points at a library built elsewhere.
const LIBRARY_ENV: &str = "RIFT_FFENC_LIB";

/// FFmpeg's log levels (`AV_LOG_*`); the library is asked for up to INFO.
const AV_LOG_WARNING: i32 = 24;
const AV_LOG_INFO: i32 = 32;

/// The peak the rate may reach over the average, in percent. At 100 the GPU
/// met the average to within a few percent at every rate WebRTC asked for
/// (Intel, Oct 9 2026); the library asks for variable bitrate, so a still
/// picture still costs next to nothing.
const PEAK_PERCENT: i32 = 100;

#[repr(C)]
struct Config {
    encoder: *const c_char,
    device: *const c_char,
    width: i32,
    height: i32,
    fps: i32,
    bitrate_bps: i64,
    peak_percent: i32,
    gop: i32,
}

#[repr(C)]
struct Packet {
    data: *const u8,
    len: usize,
    timestamp_us: i64,
    keyframe: i32,
}

/// The library's functions, as `ffenc.h` declares them.
struct Api {
    open: unsafe extern "C" fn(*const Config, *mut c_char, usize) -> *mut c_void,
    driver: unsafe extern "C" fn(*const c_void) -> *const c_char,
    set_bitrate: unsafe extern "C" fn(*mut c_void, i64),
    send: unsafe extern "C" fn(*mut c_void, *const u8, i64, i32) -> i32,
    receive: unsafe extern "C" fn(*mut c_void, *mut Packet) -> i32,
    close: unsafe extern "C" fn(*mut c_void),
    /// Kept open for as long as the functions above are called.
    _library: Library,
}

/// The library, opened once.
fn api() -> Result<&'static Api, String> {
    static API: OnceLock<Result<Api, String>> = OnceLock::new();
    API.get_or_init(load).as_ref().map_err(Clone::clone)
}

/// Where the library is: beside the app's other libraries, or where a test
/// says.
fn library_path() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os(LIBRARY_ENV) {
        return Some(PathBuf::from(path));
    }
    let exe = std::env::current_exe().ok()?;
    Some(exe.parent()?.join("lib").join(LIBRARY))
}

fn load() -> Result<Api, String> {
    let path = library_path().ok_or("no path to the FFmpeg library")?;
    // SAFETY: the library is Rift's own, built from native/ffenc, and runs no
    // code on load beyond FFmpeg's static initialisers.
    let library = unsafe { Library::new(&path) }
        .map_err(|e| format!("FFmpeg's library did not load from {}: {e}", path.display()))?;
    // SAFETY: each symbol is looked up with the type ffenc.h gives it, and the
    // version check below refuses a library built for another interface.
    unsafe {
        let abi: unsafe extern "C" fn() -> i32 = symbol(&library, "rift_ffenc_abi")?;
        if abi() != ABI {
            return Err(format!("FFmpeg's library is version {}, not {ABI}", abi()));
        }
        let set_log: unsafe extern "C" fn(Option<extern "C" fn(i32, *const c_char)>, i32) =
            symbol(&library, "rift_ffenc_set_log")?;
        set_log(Some(log_line), AV_LOG_INFO);
        Ok(Api {
            open: symbol(&library, "rift_ffenc_open")?,
            driver: symbol(&library, "rift_ffenc_driver")?,
            set_bitrate: symbol(&library, "rift_ffenc_set_bitrate")?,
            send: symbol(&library, "rift_ffenc_send")?,
            receive: symbol(&library, "rift_ffenc_receive")?,
            close: symbol(&library, "rift_ffenc_close")?,
            _library: library,
        })
    }
}

/// One of the library's functions.
///
/// # Safety
/// `T` must be the function's type as `ffenc.h` declares it.
unsafe fn symbol<T: Copy>(library: &Library, name: &str) -> Result<T, String> {
    let name = CString::new(name).map_err(|e| e.to_string())?;
    library
        .get::<T>(name.as_bytes_with_nul())
        .map(|symbol| *symbol)
        .map_err(|e| format!("FFmpeg's library has no {}: {e}", name.to_string_lossy()))
}

/// FFmpeg's own log lines, into the app's log.
extern "C" fn log_line(level: i32, line: *const c_char) {
    if line.is_null() {
        return;
    }
    // SAFETY: FFmpeg hands over a NUL-terminated line, alive for this call.
    let line = unsafe { CStr::from_ptr(line) }.to_string_lossy();
    if level <= AV_LOG_WARNING {
        log::warn!("ffmpeg: {line}");
    } else if level <= AV_LOG_INFO {
        log::info!("ffmpeg: {line}");
    } else {
        log::debug!("ffmpeg: {line}");
    }
}

/// FFmpeg's name for the encoder of `codec`.
fn encoder_name(codec: GpuCodec) -> Option<&'static CStr> {
    match codec {
        GpuCodec::H264 => Some(c"h264_vaapi"),
        GpuCodec::Av1 => None,
    }
}

/// The GPUs VAAPI can open, as their render nodes, in order.
fn render_nodes() -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir("/dev/dri") else {
        return Vec::new();
    };
    let mut nodes: Vec<PathBuf> = entries
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("renderD"))
        })
        .collect();
    nodes.sort();
    nodes
}

/// The GPU that encodes H264 through VAAPI here, and its driver's name: the
/// first render node that opens an encoder. Found once, since opening one
/// takes a moment and the GPUs do not change under a running app.
fn h264_device() -> Option<&'static (CString, String)> {
    static DEVICE: OnceLock<Option<(CString, String)>> = OnceLock::new();
    DEVICE
        .get_or_init(|| {
            let api = match api() {
                Ok(api) => api,
                Err(reason) => {
                    log::info!("encoder: no FFmpeg here: {reason}");
                    return None;
                }
            };
            for node in render_nodes() {
                let Ok(device) = CString::new(node.to_string_lossy().as_bytes()) else {
                    continue;
                };
                let probe = EncoderSettings {
                    codec: GpuCodec::H264,
                    width: 640,
                    height: 360,
                    fps: 30,
                    max_bitrate_bps: 1_000_000,
                    start_bitrate_bps: 1_000_000,
                };
                match open_raw(api, &probe, &device) {
                    Ok(raw) => {
                        // SAFETY: `raw` is a live encoder from this library,
                        // closed right after.
                        let driver = unsafe { driver_name(api, raw) };
                        unsafe { (api.close)(raw) };
                        log::info!(
                            "encoder: VAAPI on {} ({driver}) encodes H264",
                            node.display()
                        );
                        return Some((device, driver));
                    }
                    Err(reason) => {
                        log::info!("encoder: no VAAPI H264 on {}: {reason}", node.display())
                    }
                }
            }
            None
        })
        .as_ref()
}

/// Whether FFmpeg will encode `codec` on a GPU here. Asked once per run.
pub(crate) fn opens(codec: GpuCodec) -> bool {
    #[cfg(test)]
    if super::test_hooks::NO_GPU.load(std::sync::atomic::Ordering::Relaxed) {
        return false;
    }
    codec == GpuCodec::H264 && h264_device().is_some()
}

fn open_raw(api: &Api, settings: &EncoderSettings, device: &CStr) -> Result<*mut c_void, String> {
    let encoder = encoder_name(settings.codec)
        .ok_or_else(|| format!("FFmpeg is not used for {} here", settings.codec))?;
    let config = Config {
        encoder: encoder.as_ptr(),
        device: device.as_ptr(),
        width: settings.width as i32,
        height: settings.height as i32,
        fps: settings.fps as i32,
        bitrate_bps: i64::from(worker::start_bitrate(settings)),
        peak_percent: PEAK_PERCENT,
        gop: (settings.fps * GOP_SECONDS) as i32,
    };
    let mut error = [0 as c_char; 256];
    // SAFETY: `config` and the strings it points at outlive the call, and
    // `error` is as long as it is said to be.
    let raw = unsafe { (api.open)(&config, error.as_mut_ptr(), error.len()) };
    if raw.is_null() {
        // SAFETY: the library writes a NUL-terminated reason into `error`.
        let reason = unsafe { CStr::from_ptr(error.as_ptr()) }.to_string_lossy();
        return Err(if reason.is_empty() {
            "the encoder did not open".to_string()
        } else {
            reason.into_owned()
        });
    }
    Ok(raw)
}

/// # Safety
/// `raw` must be a live encoder from `api`.
unsafe fn driver_name(api: &Api, raw: *const c_void) -> String {
    let name = (api.driver)(raw);
    if name.is_null() {
        return "an unnamed driver".to_string();
    }
    CStr::from_ptr(name).to_string_lossy().into_owned()
}

/// FFmpeg's VAAPI encoder opened for a share, as the encoder thread drives it.
pub(super) struct FfmpegSession {
    api: &'static Api,
    raw: *mut c_void,
    sink: SharedSink,
    settings: EncoderSettings,
    device: &'static CStr,
    /// Pictures encoded so far, and whether the encoder was opened again
    /// after failing the first.
    pictures: u64,
    reopened: bool,
    /// An IDR sent without SPS and PPS gets the last ones put back in front,
    /// since a viewer can only start from one that has them.
    parameter_sets: ParameterSets,
}

// SAFETY: the encoder is used from the one thread that owns the session.
unsafe impl Send for FfmpegSession {}

/// Open FFmpeg's encoder on the GPU [`opens`] found, delivering to `sink`.
pub(super) fn open(
    settings: &EncoderSettings,
    sink: SharedSink,
    _failed: Arc<AtomicBool>,
) -> Result<(FfmpegSession, String), String> {
    let api = api()?;
    let (device, driver) = h264_device().ok_or("no GPU here encodes H264 through VAAPI")?;
    let raw = open_raw(api, settings, device)?;
    Ok((
        FfmpegSession {
            api,
            raw,
            sink,
            settings: *settings,
            device,
            pictures: 0,
            reopened: false,
            parameter_sets: ParameterSets::default(),
        },
        format!("VAAPI on {driver}"),
    ))
}

impl Session for FfmpegSession {
    fn set_bitrate(&mut self, bps: u32) -> Result<(), String> {
        // SAFETY: `raw` is live until the session drops.
        unsafe { (self.api.set_bitrate)(self.raw, i64::from(bps)) };
        Ok(())
    }

    fn encode(&mut self, frame: &Nv12Frame, keyframe: bool) -> Result<(), String> {
        match self.encode_once(frame, keyframe) {
            // Intel's driver (Alder Lake, Oct 9 2026) failed about one first
            // picture in four inside the app, asked exactly what it is asked
            // when it works; opened again, it works. A failure later on is the
            // encoder's, and the share moves to VP9.
            Err(reason) if self.pictures == 0 && !self.reopened => {
                log::warn!(
                    "encoder: the first picture failed ({reason}); opening the encoder again"
                );
                self.reopened = true;
                let raw = open_raw(self.api, &self.settings, self.device)?;
                // SAFETY: the old encoder is closed once, here, and replaced.
                unsafe { (self.api.close)(self.raw) };
                self.raw = raw;
                self.encode_once(frame, true)
            }
            result => result,
        }
    }
}

impl FfmpegSession {
    fn encode_once(&mut self, frame: &Nv12Frame, keyframe: bool) -> Result<(), String> {
        // SAFETY: `raw` is live, and the picture is copied to the GPU before
        // the call returns.
        let sent = unsafe {
            (self.api.send)(
                self.raw,
                frame.data.as_ptr(),
                frame.timestamp_us,
                i32::from(keyframe),
            )
        };
        if sent < 0 {
            return Err(format!("FFmpeg refused a picture ({sent})"));
        }
        loop {
            let mut packet = Packet {
                data: std::ptr::null(),
                len: 0,
                timestamp_us: 0,
                keyframe: 0,
            };
            // SAFETY: `raw` is live; the packet's bytes stay valid until the
            // next call, and are copied out before it.
            let got = unsafe { (self.api.receive)(self.raw, &mut packet) };
            if got < 0 {
                return Err(format!("FFmpeg failed a picture ({got})"));
            }
            if got == 0 || packet.data.is_null() {
                self.pictures += 1;
                return Ok(());
            }
            // SAFETY: as above.
            let payload = unsafe { std::slice::from_raw_parts(packet.data, packet.len) };
            let keyframe = packet.keyframe != 0 || h264::is_idr(payload);
            let payload = self.parameter_sets.complete(payload.to_vec());
            self.sink.lock().unwrap().deliver(Encoded {
                codec: self.settings.codec,
                payload: &payload,
                timestamp_us: packet.timestamp_us,
                keyframe,
            });
        }
    }
}

impl Drop for FfmpegSession {
    fn drop(&mut self) {
        // SAFETY: the encoder is closed once, here.
        unsafe { (self.api.close)(self.raw) };
    }
}
