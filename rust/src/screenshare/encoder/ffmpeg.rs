//! H264 on a GPU through FFmpeg: its NVENC encoder for NVIDIA's GPUs on both
//! systems, its VAAPI encoder for Intel's and AMD's on Linux, and on Windows
//! its Quick Sync encoder for Intel's and its AMF encoder for AMD's.
//!
//! LiveKit has a VAAPI encoder of its own, but on AMD (RX 9070 XT, Mesa 26.2,
//! Oct 9 2026) it stalled the viewer for seconds at a time and made 34 of 60
//! pictures a second, where FFmpeg's `h264_vaapi` on the same GPU was clean.
//! Its NVENC encoder is built from NVIDIA's SDK samples, under a licence the
//! GPL client cannot carry; FFmpeg's reaches NVIDIA's driver through MIT
//! headers alone, opening its libraries at run time.
//! On Windows LiveKit has no GPU encoder at all, and Media Foundation's, which
//! Rift used before, ran past WebRTC's target whenever the target was below
//! what the picture cost, so it was dropped (`CALLS.md`, "Encoding a share on
//! the GPU").
//! FFmpeg cannot be linked into this crate beside libwebrtc, which carries
//! Chromium's FFmpeg under the same symbol names, so it lives in a library of
//! its own (`native/ffenc`), opened at run time. FFmpeg's VAAPI and AMF
//! encoders send the bitrate to the GPU only when they open, and its NVENC
//! encoder made a keyframe of every move, so the build patches them
//! (`third_party/ffmpeg/RIFT_PATCHES.md`).
use super::h264::{self, ParameterSets};
use super::timings::EncodeTimes;
use super::worker::{self, EncodeError, Session, SharedSink, GOP_SECONDS};
use super::{Encoded, EncoderInput, EncoderSettings, GpuCodec};
#[cfg(target_os = "linux")]
use crate::screenshare::{pw_stream::RiftDmabuf, resolution};
use libloading::Library;
use std::ffi::{c_char, c_void, CStr, CString};
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

/// The library's interface version this crate was written against
/// (`RIFT_FFENC_ABI` in `ffenc.h`).
const ABI: i32 = 8;

/// The library's name: in the bundle's `lib` folder on Linux, beside the app
/// on Windows.
#[cfg(target_os = "linux")]
const LIBRARY: &str = "lib/librift_ffenc.so";
#[cfg(target_os = "windows")]
const LIBRARY: &str = "rift_ffenc.dll";

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
    max_bitrate_bps: i64,
    delay_frames: i32,
    high: i32,
}

/// Where the upright picture goes inside the encoded size (`RiftRect`).
#[cfg(target_os = "linux")]
#[repr(C)]
struct Place {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
}

/// `rift_ffenc_send_dmabuf`'s answer for a format and modifier VAAPI would
/// not map (`RIFT_FFENC_IMPORT_FAILED`).
#[cfg(target_os = "linux")]
const IMPORT_FAILED: i32 = -0x5249_4D50;

/// FFmpeg's `AVERROR(EAGAIN)`: `rift_ffenc_repeat` before any DMA-BUF.
#[cfg(target_os = "linux")]
const AVERROR_EAGAIN: i32 = -11;

#[repr(C)]
struct Packet {
    data: *const u8,
    len: usize,
    timestamp_us: i64,
    keyframe: i32,
}

/// The library's encoder functions, as `ffenc.h` declares them.
struct Api {
    open: unsafe extern "C" fn(*const Config, *mut c_char, usize) -> *mut c_void,
    driver: unsafe extern "C" fn(*const c_void) -> *const c_char,
    set_bitrate: unsafe extern "C" fn(*mut c_void, i64),
    send: unsafe extern "C" fn(*mut c_void, *const u8, i64, i32) -> i32,
    #[cfg(target_os = "linux")]
    takes_dmabuf: unsafe extern "C" fn(*const c_void) -> i32,
    #[cfg(target_os = "linux")]
    send_dmabuf:
        unsafe extern "C" fn(*mut c_void, *const RiftDmabuf, *const Place, i64, i32) -> i32,
    #[cfg(target_os = "linux")]
    repeat: unsafe extern "C" fn(*mut c_void, i64, i32) -> i32,
    receive: unsafe extern "C" fn(*mut c_void, *mut Packet) -> i32,
    close: unsafe extern "C" fn(*mut c_void),
}

/// The library's encoder functions, looked up once.
fn api() -> Result<&'static Api, String> {
    static API: OnceLock<Result<Api, String>> = OnceLock::new();
    API.get_or_init(|| {
        let library = library()?;
        // SAFETY: each symbol is looked up with the type ffenc.h gives it,
        // in a library `library` checked is of this interface.
        unsafe {
            Ok(Api {
                open: symbol(library, "rift_ffenc_open")?,
                driver: symbol(library, "rift_ffenc_driver")?,
                set_bitrate: symbol(library, "rift_ffenc_set_bitrate")?,
                send: symbol(library, "rift_ffenc_send")?,
                #[cfg(target_os = "linux")]
                takes_dmabuf: symbol(library, "rift_ffenc_takes_dmabuf")?,
                #[cfg(target_os = "linux")]
                send_dmabuf: symbol(library, "rift_ffenc_send_dmabuf")?,
                #[cfg(target_os = "linux")]
                repeat: symbol(library, "rift_ffenc_repeat")?,
                receive: symbol(library, "rift_ffenc_receive")?,
                close: symbol(library, "rift_ffenc_close")?,
            })
        }
    })
    .as_ref()
    .map_err(Clone::clone)
}

/// The library, opened once and kept open, its version checked: also what
/// a Wayland share's PipeWire stream runs in (`pw_stream.rs`).
pub(crate) fn library() -> Result<&'static Library, String> {
    static LIBRARY: OnceLock<Result<Library, String>> = OnceLock::new();
    LIBRARY.get_or_init(load).as_ref().map_err(Clone::clone)
}

/// Where the library is: beside the app's other libraries, or where a test
/// says.
fn library_path() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os(LIBRARY_ENV) {
        return Some(PathBuf::from(path));
    }
    let exe = std::env::current_exe().ok()?;
    Some(exe.parent()?.join(LIBRARY))
}

fn load() -> Result<Library, String> {
    let path = library_path().ok_or("no path to the FFmpeg library")?;
    // SAFETY: the library is Rift's own, built from native/ffenc, and runs no
    // code on load beyond FFmpeg's static initialisers.
    let library = unsafe { Library::new(&path) }
        .map_err(|e| format!("FFmpeg's library did not load from {}: {e}", path.display()))?;
    // SAFETY: each symbol is looked up with the type ffenc.h gives it, and the
    // version check refuses a library built for another interface.
    unsafe {
        let abi: unsafe extern "C" fn() -> i32 = symbol(&library, "rift_ffenc_abi")?;
        if abi() != ABI {
            return Err(format!("FFmpeg's library is version {}, not {ABI}", abi()));
        }
        let set_log: unsafe extern "C" fn(Option<extern "C" fn(i32, *const c_char)>, i32) =
            symbol(&library, "rift_ffenc_set_log")?;
        set_log(Some(log_line), AV_LOG_INFO);
    }
    Ok(library)
}

/// One of the library's functions.
///
/// # Safety
/// `T` must be the function's type as `ffenc.h` declares it.
pub(crate) unsafe fn symbol<T: Copy>(library: &Library, name: &str) -> Result<T, String> {
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

/// An FFmpeg encoder that may make H264 here, and the GPU to open it on.
struct Candidate {
    encoder: &'static CStr,
    /// As FFmpeg names the GPU; `None` leaves it to the driver.
    device: Option<CString>,
    /// What the logs call it until it has opened and named its driver.
    label: String,
}

/// The encoders worth trying, in order: NVENC, then VAAPI on each render
/// node, first to last. NVIDIA's driver finds its own GPU, which on a laptop
/// with two is the NVIDIA one whichever drives the screen; under X11 the
/// pictures come from memory, so that does not matter. Under Wayland VAAPI
/// comes first: it takes the compositor's DMA-BUF and the picture never
/// comes to the CPU (`capture_pw.rs`), where NVENC, for now, takes it from
/// memory. [`ENCODER_ENV`] names the one to try instead.
#[cfg(target_os = "linux")]
fn candidates() -> Vec<Candidate> {
    let nvenc = Candidate {
        encoder: c"h264_nvenc",
        device: None,
        label: "NVENC".to_string(),
    };
    let mut candidates = Vec::new();
    let mut nodes: Vec<PathBuf> = std::fs::read_dir("/dev/dri")
        .into_iter()
        .flatten()
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("renderD"))
        })
        .collect();
    nodes.sort();
    candidates.extend(nodes.into_iter().filter_map(|node| {
        Some(Candidate {
            encoder: c"h264_vaapi",
            device: Some(CString::new(node.to_string_lossy().as_bytes()).ok()?),
            label: format!("VAAPI on {}", node.display()),
        })
    }));
    if super::super::capture_pw::on_wayland() {
        candidates.push(nvenc);
    } else {
        candidates.insert(0, nvenc);
    }
    named_only(candidates)
}

/// The render node a Wayland share's DMA-BUF is offered for: VAAPI's GPU,
/// when VAAPI is what encodes H264 here.
#[cfg(target_os = "linux")]
pub(crate) fn dmabuf_render_node() -> Option<String> {
    let (candidate, _) = h264_encoder()?;
    if candidate.encoder != c"h264_vaapi" {
        return None;
    }
    candidate.device.as_ref()?.to_str().ok().map(str::to_owned)
}

/// The encoders worth trying, in order: NVIDIA's, AMD's, then Intel's. Each
/// vendor's driver finds its own GPU, so there is no adapter to name; a PC
/// with Intel graphics beside an NVIDIA or AMD card gets the card's encoder,
/// as on Linux. The pictures come from memory, so which GPU the screen is on
/// does not matter. AMD's (`h264_amf`) followed a moved rate like the other
/// two on an RX 9070 XT (Oct 11 2026, `GPU_ENCODING_AMD_WINDOWS_RESULTS.md` on
/// the `gpu-encoding` branch). [`ENCODER_ENV`] names the one to try instead.
#[cfg(target_os = "windows")]
fn candidates() -> Vec<Candidate> {
    const ENCODERS: [(&CStr, &str); 3] = [
        (c"h264_nvenc", "NVENC"),
        (c"h264_amf", "AMF"),
        (c"h264_qsv", "Quick Sync"),
    ];
    named_only(
        ENCODERS
            .into_iter()
            .map(|(encoder, label)| Candidate {
                encoder,
                device: None,
                label: label.to_string(),
            })
            .collect(),
    )
}

/// The one FFmpeg encoder to try, by FFmpeg's name: Quick Sync on a PC that
/// would pick its NVIDIA or AMD card, or VAAPI on a Linux laptop with NVIDIA's
/// beside it, for a test or a bench.
const ENCODER_ENV: &str = "RIFT_FFENC_ENCODER";

/// `candidates` without those [`ENCODER_ENV`] leaves out. A test also skips
/// NVENC with `GPU_NO_NVENC`, to run VAAPI on a computer with both.
fn named_only(candidates: Vec<Candidate>) -> Vec<Candidate> {
    let named = std::env::var(ENCODER_ENV).ok();
    #[cfg(test)]
    let no_nvenc = std::env::var_os("GPU_NO_NVENC").is_some();
    #[cfg(not(test))]
    let no_nvenc = false;
    candidates
        .into_iter()
        .filter(|candidate| match &named {
            Some(named) => candidate.encoder.to_str() == Ok(named.as_str()),
            None => true,
        })
        .filter(|candidate| !(no_nvenc && candidate.encoder == c"h264_nvenc"))
        .collect()
}

/// The encoder that makes H264 here, and its driver's name: the first
/// [`candidates`] entry that opens. Found once, since opening one takes a
/// moment and the GPUs do not change under a running app.
fn h264_encoder() -> Option<&'static (Candidate, String)> {
    static ENCODER: OnceLock<Option<(Candidate, String)>> = OnceLock::new();
    ENCODER
        .get_or_init(|| {
            let api = match api() {
                Ok(api) => api,
                Err(reason) => {
                    log::info!("encoder: no FFmpeg here: {reason}");
                    return None;
                }
            };
            for candidate in candidates() {
                let probe = EncoderSettings {
                    codec: GpuCodec::H264,
                    width: 640,
                    height: 360,
                    fps: 30,
                    max_bitrate_bps: 1_000_000,
                    start_bitrate_bps: 1_000_000,
                    // Probed for what a share asks of it.
                    h264_high: super::SEND_H264_HIGH,
                };
                match open_raw(api, &probe, &candidate) {
                    Ok(raw) => {
                        // SAFETY: `raw` is a live encoder from this library,
                        // closed right after.
                        let driver = unsafe { driver_name(api, raw) };
                        unsafe { (api.close)(raw) };
                        log::info!("encoder: {} ({driver}) encodes H264", candidate.label);
                        return Some((candidate, driver));
                    }
                    Err(reason) => {
                        log::info!("encoder: no H264 from {}: {reason}", candidate.label)
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
    codec == GpuCodec::H264 && h264_encoder().is_some()
}

/// NVENC's `delay` for a share at `fps`: 2 above 60 fps, which has it hold
/// one picture while the next goes in, and 0, nothing held, at 60 and below.
///
/// FFmpeg's NVENC waits for each picture to be encoded before taking the
/// next, and NVIDIA's driver drops an RTX 3070 Ti Laptop to its idle clocks
/// (P8, video 555 MHz) a few seconds into a share, after which a 1080p
/// picture took 11.4 ms: 87 fps at 120. Holding one, the wait overlaps the
/// next picture: 1.4 ms a picture, the GPU settling at P3, and the viewer at
/// 118.0 fps (Oct 16 2026, Windows). On Linux the same GPU stayed at P0 and
/// made 120 either way, a picture taking 0.3 ms to send held and 2.1 ms not
/// (same day, a 960x1000 window). At 60 the wait fits in a picture's time, so
/// nothing is held, and the picture is not a frame later. FFmpeg hands a
/// picture out once `delay` are ready or waiting, and the newest is ready as
/// soon as it is in, so 1 holds nothing.
fn delay_frames(fps: u32) -> i32 {
    if fps > 60 {
        2
    } else {
        0
    }
}

fn open_raw(
    api: &Api,
    settings: &EncoderSettings,
    candidate: &Candidate,
) -> Result<*mut c_void, String> {
    if settings.codec != GpuCodec::H264 {
        return Err(format!("FFmpeg is not used for {} here", settings.codec));
    }
    let config = Config {
        encoder: candidate.encoder.as_ptr(),
        device: candidate
            .device
            .as_ref()
            .map_or(std::ptr::null(), |device| device.as_ptr()),
        width: settings.width as i32,
        height: settings.height as i32,
        fps: settings.fps as i32,
        bitrate_bps: i64::from(worker::start_bitrate(settings)),
        peak_percent: PEAK_PERCENT,
        gop: (settings.fps * GOP_SECONDS) as i32,
        max_bitrate_bps: i64::from(settings.max_bitrate_bps),
        delay_frames: delay_frames(settings.fps),
        high: i32::from(settings.h264_high),
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

/// FFmpeg's encoder opened for a share, as the encoder thread drives it.
pub(super) struct FfmpegSession {
    api: &'static Api,
    raw: *mut c_void,
    sink: SharedSink,
    settings: EncoderSettings,
    candidate: &'static Candidate,
    /// Pictures encoded so far, and whether the encoder was opened again
    /// after failing the first.
    pictures: u64,
    reopened: bool,
    /// An IDR sent without SPS and PPS gets the last ones put back in front,
    /// since a viewer can only start from one that has them.
    parameter_sets: ParameterSets,
    /// Where each picture's time goes, for the log.
    times: EncodeTimes,
    /// Whether the last picture was a DMA-BUF, which the library keeps on
    /// the GPU for a still screen's repeats; one from memory is not kept.
    repeatable: bool,
}

// SAFETY: the encoder is used from the one thread that owns the session.
unsafe impl Send for FfmpegSession {}

/// Open FFmpeg's encoder on the GPU [`opens`] found, delivering to `sink`.
pub(super) fn open(
    settings: &EncoderSettings,
    sink: SharedSink,
) -> Result<(FfmpegSession, String), String> {
    let api = api()?;
    let (candidate, driver) = h264_encoder().ok_or("no GPU here encodes H264 through FFmpeg")?;
    let raw = open_raw(api, settings, candidate)?;
    Ok((
        FfmpegSession {
            api,
            raw,
            sink,
            settings: *settings,
            candidate,
            pictures: 0,
            reopened: false,
            parameter_sets: ParameterSets::default(),
            times: EncodeTimes::default(),
            repeatable: false,
        },
        format!("{} ({driver})", candidate.label),
    ))
}

impl Session for FfmpegSession {
    fn set_bitrate(&mut self, bps: u32) -> Result<(), String> {
        // SAFETY: `raw` is live until the session drops.
        unsafe { (self.api.set_bitrate)(self.raw, i64::from(bps)) };
        Ok(())
    }

    fn encode(&mut self, input: &EncoderInput, keyframe: bool) -> Result<(), EncodeError> {
        match self.encode_once(input, keyframe) {
            // Intel's driver (Alder Lake, Oct 9 2026) failed about one first
            // picture in four inside the app, asked exactly what it is asked
            // when it works; opened again, it works. A failure later on is the
            // encoder's, and the share moves to VP9.
            Err(EncodeError::Failed(reason)) if self.pictures == 0 && !self.reopened => {
                log::warn!(
                    "encoder: the first picture failed ({reason}); opening the encoder again"
                );
                self.reopened = true;
                let raw = open_raw(self.api, &self.settings, self.candidate)
                    .map_err(EncodeError::Failed)?;
                // SAFETY: the old encoder is closed once, here, and replaced.
                unsafe { (self.api.close)(self.raw) };
                self.raw = raw;
                self.encode_once(input, true)
            }
            result => result,
        }
    }

    #[cfg(target_os = "linux")]
    fn repeat(&mut self, timestamp_us: i64, keyframe: bool) -> Result<bool, String> {
        if !self.repeatable {
            return Ok(false);
        }
        let started = Instant::now();
        // SAFETY: `raw` is live; the picture repeated is the library's own.
        let sent = unsafe { (self.api.repeat)(self.raw, timestamp_us, i32::from(keyframe)) };
        if sent == AVERROR_EAGAIN {
            return Ok(false);
        }
        if sent < 0 {
            return Err(format!("FFmpeg refused to repeat a picture ({sent})"));
        }
        self.receive(started)?;
        Ok(true)
    }

    #[cfg(not(target_os = "linux"))]
    fn repeat(&mut self, _timestamp_us: i64, _keyframe: bool) -> Result<bool, String> {
        Ok(false)
    }

    #[cfg(target_os = "linux")]
    fn takes_dmabuf(&self) -> bool {
        // SAFETY: `raw` is live.
        unsafe { (self.api.takes_dmabuf)(self.raw) != 0 }
    }

    #[cfg(not(target_os = "linux"))]
    fn takes_dmabuf(&self) -> bool {
        false
    }
}

impl FfmpegSession {
    fn encode_once(&mut self, input: &EncoderInput, keyframe: bool) -> Result<(), EncodeError> {
        let started = Instant::now();
        match input {
            EncoderInput::Nv12(frame) => {
                // SAFETY: `raw` is live, and the picture is copied before the
                // call returns.
                let sent = unsafe {
                    (self.api.send)(
                        self.raw,
                        frame.data.as_ptr(),
                        frame.timestamp_us,
                        i32::from(keyframe),
                    )
                };
                if sent < 0 {
                    return Err(EncodeError::Failed(format!(
                        "FFmpeg refused a picture ({sent})"
                    )));
                }
                self.repeatable = false;
            }
            #[cfg(target_os = "linux")]
            EncoderInput::DmaBuf(frame) => self.send_dmabuf(frame, keyframe)?,
        }
        self.receive(started).map_err(EncodeError::Failed)
    }

    /// Hand the library a DMA-BUF, letterboxed into the encoded size by the
    /// same rule as a picture from memory (`frames::fit`).
    #[cfg(target_os = "linux")]
    fn send_dmabuf(
        &mut self,
        frame: &super::DmaBufFrame,
        keyframe: bool,
    ) -> Result<(), EncodeError> {
        if !self.takes_dmabuf() {
            return Err(EncodeError::Failed(format!(
                "{} takes no DMA-BUF",
                self.candidate.label
            )));
        }
        let Some(dmabuf) = frame.picture.dmabuf() else {
            return Err(EncodeError::Failed(
                "a picture in memory was sent as a DMA-BUF".to_string(),
            ));
        };
        let target = resolution::Size {
            width: self.settings.width,
            height: self.settings.height,
        };
        let place = resolution::letterbox(frame.picture.size(), target).map(|rect| Place {
            x: rect.x as i32,
            y: rect.y as i32,
            width: rect.width as i32,
            height: rect.height as i32,
        });
        // SAFETY: `raw` is live, and the buffer and its fds stay the
        // picture's until after the call returns, by which the GPU has
        // copied it.
        let sent = unsafe {
            (self.api.send_dmabuf)(
                self.raw,
                dmabuf,
                place
                    .as_ref()
                    .map_or(std::ptr::null(), |place| place as *const Place),
                frame.timestamp_us,
                i32::from(keyframe),
            )
        };
        if sent == IMPORT_FAILED {
            return Err(EncodeError::ImportFailed {
                drm_format: dmabuf.drm_format,
                modifier: dmabuf.modifier,
            });
        }
        if sent < 0 {
            return Err(EncodeError::Failed(format!(
                "FFmpeg refused a DMA-BUF ({sent})"
            )));
        }
        self.repeatable = true;
        Ok(())
    }

    /// Hand the sink what the encoder has ready, for a picture sent at
    /// `started`.
    fn receive(&mut self, started: Instant) -> Result<(), String> {
        let send = started.elapsed();
        let mut deliver = Duration::ZERO;
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
                self.note_times(send, started.elapsed() - send - deliver, deliver);
                return Ok(());
            }
            // SAFETY: as above.
            let payload = unsafe { std::slice::from_raw_parts(packet.data, packet.len) };
            let delivering = Instant::now();
            let keyframe = packet.keyframe != 0 || h264::is_idr(payload);
            let payload = self.parameter_sets.complete(payload.to_vec());
            self.sink.lock().unwrap().deliver(Encoded {
                payload: &payload,
                timestamp_us: packet.timestamp_us,
                keyframe,
            });
            deliver += delivering.elapsed();
        }
    }

    /// Count one picture's times, and say them every few seconds.
    fn note_times(&mut self, send: Duration, encode: Duration, deliver: Duration) {
        self.times.add(send, encode, deliver);
        if let Some(report) = self.times.report(Instant::now()) {
            log::info!(
                "encoder: {}: send {:.1} ms, encode {:.1} ms, deliver {:.1} ms a picture over {} \
                 (longest {:.1})",
                self.candidate.label,
                report.send_ms,
                report.encode_ms,
                report.deliver_ms,
                report.pictures,
                report.longest_ms,
            );
        }
    }
}

impl Drop for FfmpegSession {
    fn drop(&mut self) {
        // SAFETY: the encoder is closed once, here.
        unsafe { (self.api.close)(self.raw) };
    }
}
