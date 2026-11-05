//! Linux: FFmpeg's GPU decoders, in Rift's FFmpeg library
//! (`native/ffenc/ffdec.h`), on the GPU that draws the screen. On Intel or
//! AMD through VAAPI, each picture leaving as two DMA-BUF layers, which the
//! runner imports; on NVIDIA through CUDA, each picture copied by the library
//! into the runner's GL textures as the runner draws it.

use super::super::frames::{CopyToGl, GlClose, Picture, WatchPlanes, IN_CUDA, ON_GPU};
use super::Codec;
use crate::screenshare::encoder::ffmpeg::{library, symbol};
use crate::screenshare::encoder::gpu_choice::{self, WatchDecoder};
use std::ffi::{c_char, c_void, CStr, CString};
use std::fmt;
use std::sync::OnceLock;

/// FFmpeg's AVERROR(ENOSYS): the GPU cannot decode this stream.
const NO_GPU_DECODER: i32 = -38;

/// `RiftFfdecApi`.
const VAAPI: i32 = 0;
const CUDA: i32 = 1;

/// `RiftFfdecMemory`'s CUDA.
const MEMORY_CUDA: i32 = 1;

#[repr(C)]
struct Config {
    codec: i32,
    device: *const c_char,
    api: i32,
    /// Windows' D3D11 device; none here.
    d3d11_device: *mut c_void,
}

/// `RiftFfdecPicture`, as `ffdec.h` declares it.
#[repr(C)]
struct RawPicture {
    width: i32,
    height: i32,
    planes: i32,
    memory: i32,
    matrix: i32,
    full_range: i32,
    formats: [u32; 4],
    fds: [i32; 4],
    offsets: [u32; 4],
    pitches: [u32; 4],
    modifiers: [u64; 4],
    timestamp_us: i64,
    held: *mut c_void,
    /// Windows' D3D11 slice; never one here.
    d3d11_texture: *mut c_void,
    d3d11_slice: i32,
}

/// The library's decoder functions, as `ffdec.h` declares them.
struct Api {
    open: unsafe extern "C" fn(*const Config, *mut c_char, usize) -> *mut c_void,
    driver: unsafe extern "C" fn(*const c_void) -> *const c_char,
    send: unsafe extern "C" fn(*mut c_void, *const u8, usize, i64) -> i32,
    receive: unsafe extern "C" fn(*mut c_void, *mut RawPicture) -> i32,
    release: unsafe extern "C" fn(*mut RawPicture),
    close: unsafe extern "C" fn(*mut c_void),
    copy_to_gl: CopyToGl,
    gl_close: GlClose,
}

fn api() -> Result<&'static Api, String> {
    static API: OnceLock<Result<Api, String>> = OnceLock::new();
    API.get_or_init(|| {
        let library = library()?;
        // SAFETY: each symbol is looked up with the type ffdec.h gives it, in
        // a library `library` checked is of this interface.
        unsafe {
            Ok(Api {
                open: symbol(library, "rift_ffdec_open")?,
                driver: symbol(library, "rift_ffdec_driver")?,
                send: symbol(library, "rift_ffdec_send")?,
                receive: symbol(library, "rift_ffdec_receive")?,
                release: symbol(library, "rift_ffdec_release")?,
                close: symbol(library, "rift_ffdec_close")?,
                copy_to_gl: symbol(library, "rift_ffdec_copy_to_gl")?,
                gl_close: symbol(library, "rift_ffdec_gl_close")?,
            })
        }
    })
    .as_ref()
    .map_err(Clone::clone)
}

/// The GPU watched shares decode on.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Gpu {
    node: String,
    cuda: bool,
}

impl fmt::Display for Gpu {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let through = if self.cuda { "CUDA" } else { "VAAPI" };
        write!(f, "{}, through {through}", self.node)
    }
}

impl Gpu {
    /// Whether the runner can draw what this GPU decodes: always, here, where
    /// the runner's own answer (`takesGpuPictures`) says all there is to say.
    pub(crate) fn drawn_by_runner(&self) -> bool {
        true
    }
}

#[cfg(test)]
impl Gpu {
    /// Whether the driver says it decodes [codec], asked through libva:
    /// `None` through CUDA, or when libva cannot be asked.
    pub(crate) fn decodes(&self, codec: Codec) -> Option<bool> {
        if self.cuda {
            return None;
        }
        // va.h's VAProfile values for each codec, and VAEntrypointVLD.
        let profiles: &[i32] = match codec {
            Codec::H264 => &[13, 6, 7],
            Codec::Vp8 => &[14],
            Codec::Vp9 => &[19],
        };
        const VLD: i32 = 1;
        type Display = *mut c_void;
        // SAFETY: libva's functions, looked up with the types va.h and
        // va_drm.h give them, on a display opened and ended here.
        unsafe {
            let va = libloading::Library::new("libva.so.2").ok()?;
            let drm = libloading::Library::new("libva-drm.so.2").ok()?;
            let get_display: libloading::Symbol<unsafe extern "C" fn(i32) -> Display> =
                drm.get(b"vaGetDisplayDRM\0").ok()?;
            let initialize: libloading::Symbol<
                unsafe extern "C" fn(Display, *mut i32, *mut i32) -> i32,
            > = va.get(b"vaInitialize\0").ok()?;
            let terminate: libloading::Symbol<unsafe extern "C" fn(Display) -> i32> =
                va.get(b"vaTerminate\0").ok()?;
            let max_entrypoints: libloading::Symbol<unsafe extern "C" fn(Display) -> i32> =
                va.get(b"vaMaxNumEntrypoints\0").ok()?;
            let entrypoints: libloading::Symbol<
                unsafe extern "C" fn(Display, i32, *mut i32, *mut i32) -> i32,
            > = va.get(b"vaQueryConfigEntrypoints\0").ok()?;
            let file = std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(&self.node)
                .ok()?;
            let display = get_display(std::os::fd::AsRawFd::as_raw_fd(&file));
            if display.is_null() {
                return None;
            }
            let (mut major, mut minor) = (0, 0);
            if initialize(display, &mut major, &mut minor) != 0 {
                return None;
            }
            let mut list = vec![0i32; max_entrypoints(display).max(1) as usize];
            let decodes = profiles.iter().any(|&profile| {
                let mut count = 0;
                entrypoints(display, profile, list.as_mut_ptr(), &mut count) == 0
                    && list[..count as usize].contains(&VLD)
            });
            terminate(display);
            Some(decodes)
        }
    }
}

/// The GPU a watched share decodes on, or why none does: the card that draws
/// the screen (`gpu_choice::watch_decoder`), under Wayland, where GTK draws
/// with EGL on that card. GTK 3 draws with GLX under X11, which imports no
/// DMA-BUFs.
pub(super) fn device() -> Result<Gpu, String> {
    let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some()
        && !std::env::var("GDK_BACKEND").is_ok_and(|b| b.trim_start().starts_with("x11"));
    if !wayland {
        return Err("not under Wayland".to_string());
    }
    let cards = gpu_choice::read_cards();
    let gpu = match gpu_choice::watch_decoder(&cards) {
        Some(WatchDecoder::Vaapi(node)) => Gpu {
            node: node.to_owned(),
            cuda: false,
        },
        Some(WatchDecoder::Cuda(node)) => Gpu {
            node: node.to_owned(),
            cuda: true,
        },
        None => return Err("no GPU that draws the screen has a render node".to_string()),
    };
    api()?;
    Ok(gpu)
}

/// One share's decoder, used on its one thread.
pub(crate) struct Decoder {
    api: &'static Api,
    raw: *mut c_void,
}

// SAFETY: FFmpeg's decoder is used from one thread at a time; it only moves
// to the share's thread once, before its first use.
unsafe impl Send for Decoder {}

pub(crate) enum DecodeError {
    /// The GPU cannot decode this stream.
    NoGpuDecoder,
    Failed(i32),
}

impl Decoder {
    pub(crate) fn open(codec: Codec, gpu: &Gpu) -> Result<Decoder, String> {
        let api = api()?;
        let device = CString::new(gpu.node.as_str()).map_err(|e| e.to_string())?;
        let config = Config {
            codec: match codec {
                Codec::H264 => 1,
                Codec::Vp8 => 2,
                Codec::Vp9 => 3,
            },
            device: device.as_ptr(),
            api: if gpu.cuda { CUDA } else { VAAPI },
            d3d11_device: std::ptr::null_mut(),
        };
        let mut error = [0 as c_char; 256];
        // SAFETY: the config and the error buffer outlive the call, which
        // writes at most `error.len()` bytes into it.
        let raw = unsafe { (api.open)(&config, error.as_mut_ptr(), error.len()) };
        if raw.is_null() {
            // SAFETY: the library wrote a NUL-terminated reason into it.
            let reason = unsafe { CStr::from_ptr(error.as_ptr()) }.to_string_lossy();
            return Err(format!("the GPU decoder did not open: {reason}"));
        }
        Ok(Decoder { api, raw })
    }

    /// Whether the device it decodes on was removed: never asked here, where
    /// keyframes that keep failing give up instead.
    pub(crate) fn device_lost(&self) -> bool {
        false
    }

    /// The GPU's driver, as it names itself.
    pub(crate) fn driver(&self) -> String {
        // SAFETY: an open decoder answers a string it keeps.
        unsafe { CStr::from_ptr((self.api.driver)(self.raw)) }
            .to_string_lossy()
            .into_owned()
    }

    /// Decodes one access unit, answering what came out of it: one picture
    /// for each in, since a share has none out of order.
    pub(crate) fn decode(
        &mut self,
        data: &[u8],
        timestamp_us: i64,
    ) -> Result<Vec<Decoded>, DecodeError> {
        // SAFETY: the decoder is open, and the data lives through the call,
        // which copies it.
        let sent = unsafe { (self.api.send)(self.raw, data.as_ptr(), data.len(), timestamp_us) };
        match sent {
            0 => {}
            NO_GPU_DECODER => return Err(DecodeError::NoGpuDecoder),
            err => return Err(DecodeError::Failed(err)),
        }
        let mut pictures = Vec::with_capacity(1);
        loop {
            // SAFETY: an empty picture the call fills in; on 1 it holds a
            // surface, which `Decoded` releases.
            let mut raw: RawPicture = unsafe { std::mem::zeroed() };
            match unsafe { (self.api.receive)(self.raw, &mut raw) } {
                1 => pictures.push(Decoded { raw, api: self.api }),
                0 => return Ok(pictures),
                NO_GPU_DECODER => return Err(DecodeError::NoGpuDecoder),
                err => return Err(DecodeError::Failed(err)),
            }
        }
    }
}

impl Drop for Decoder {
    fn drop(&mut self) {
        // SAFETY: opened by `open`, closed once. Pictures still lent out keep
        // their own hold on their surfaces.
        unsafe { (self.api.close)(self.raw) };
    }
}

/// A picture decoded on the GPU, holding its surface until it goes.
pub(crate) struct Decoded {
    raw: RawPicture,
    api: &'static Api,
}

// SAFETY: the picture is a reference to a GPU surface, which FFmpeg lets go
// of from any thread (`rift_ffdec_release`), and the runner copies from on
// its own thread while it is lent (`rift_ffdec_copy_to_gl`).
unsafe impl Send for Decoded {}

impl Decoded {
    pub(crate) fn size(&self) -> (u32, u32) {
        (self.raw.width as u32, self.raw.height as u32)
    }
}

impl Picture for Decoded {
    fn planes(&self) -> WatchPlanes {
        let r = &self.raw;
        let colour = WatchPlanes {
            matrix: r.matrix as u32,
            full_range: r.full_range as u32,
            ..WatchPlanes::sized(r.width as u32, r.height as u32)
        };
        if r.memory == MEMORY_CUDA {
            return WatchPlanes {
                kind: IN_CUDA,
                // Where the picture lies until it is dropped: inside the box
                // the slot holds it in, which moving the box leaves in place.
                picture: (r as *const RawPicture).cast(),
                copy_to_gl: Some(self.api.copy_to_gl),
                gl_close: Some(self.api.gl_close),
                ..colour
            };
        }
        WatchPlanes {
            kind: ON_GPU,
            formats: [r.formats[0], r.formats[1]],
            fds: [r.fds[0], r.fds[1]],
            offsets: [r.offsets[0], r.offsets[1]],
            pitches: [r.pitches[0], r.pitches[1]],
            modifiers: [r.modifiers[0], r.modifiers[1]],
            ..colour
        }
    }
}

impl Drop for Decoded {
    fn drop(&mut self) {
        // SAFETY: a picture the library handed out, released once.
        unsafe { (self.api.release)(&mut self.raw) };
    }
}
