//! Linux: FFmpeg's VAAPI decoders, in Rift's FFmpeg library
//! (`native/ffenc/ffdec.h`), on the Intel or AMD GPU that draws the screen.
//! Each picture leaves as two DMA-BUF layers, which the runner imports.

use super::super::frames::{Picture, WatchPlanes, ON_GPU};
use super::Codec;
use crate::screenshare::encoder::ffmpeg::{library, symbol};
use crate::screenshare::encoder::gpu_choice;
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::OnceLock;

/// FFmpeg's AVERROR(ENOSYS): the GPU cannot decode this stream.
const NO_GPU_DECODER: i32 = -38;

#[repr(C)]
struct Config {
    codec: i32,
    device: *const c_char,
}

/// `RiftFfdecPicture`, as `ffdec.h` declares it.
#[repr(C)]
struct RawPicture {
    width: i32,
    height: i32,
    planes: i32,
    formats: [u32; 4],
    fds: [i32; 4],
    offsets: [u32; 4],
    pitches: [u32; 4],
    modifiers: [u64; 4],
    timestamp_us: i64,
    held: *mut c_void,
}

/// The library's decoder functions, as `ffdec.h` declares them.
struct Api {
    open: unsafe extern "C" fn(*const Config, *mut c_char, usize) -> *mut c_void,
    driver: unsafe extern "C" fn(*const c_void) -> *const c_char,
    send: unsafe extern "C" fn(*mut c_void, *const u8, usize, i64) -> i32,
    receive: unsafe extern "C" fn(*mut c_void, *mut RawPicture) -> i32,
    release: unsafe extern "C" fn(*mut RawPicture),
    close: unsafe extern "C" fn(*mut c_void),
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
            })
        }
    })
    .as_ref()
    .map_err(Clone::clone)
}

/// The GPU a watched share decodes on, or why none does: the Intel or AMD
/// card that draws the screen, under Wayland, where GTK draws with EGL, which
/// imports DMA-BUFs. GTK 3 draws with GLX under X11, which cannot.
pub(super) fn device() -> Result<String, String> {
    let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some()
        && !std::env::var("GDK_BACKEND").is_ok_and(|b| b.trim_start().starts_with("x11"));
    if !wayland {
        return Err("not under Wayland".to_string());
    }
    let cards = gpu_choice::read_cards();
    let Some(node) = gpu_choice::intel_or_amd_drawing(&cards) else {
        return Err("no Intel or AMD GPU draws the screen".to_string());
    };
    api()?;
    Ok(node.to_owned())
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
    pub(crate) fn open(codec: Codec, device: &str) -> Result<Decoder, String> {
        let api = api()?;
        let device = CString::new(device).map_err(|e| e.to_string())?;
        let config = Config {
            codec: match codec {
                Codec::H264 => 1,
                Codec::Vp8 => 2,
                Codec::Vp9 => 3,
            },
            device: device.as_ptr(),
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
                1 => pictures.push(Decoded {
                    raw,
                    release: self.api.release,
                }),
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
    release: unsafe extern "C" fn(*mut RawPicture),
}

// SAFETY: the picture is a reference to a GPU surface, which FFmpeg lets go
// of from any thread (`rift_ffdec_release`).
unsafe impl Send for Decoded {}

impl Decoded {
    pub(crate) fn size(&self) -> (u32, u32) {
        (self.raw.width as u32, self.raw.height as u32)
    }
}

impl Picture for Decoded {
    fn planes(&self) -> WatchPlanes {
        let r = &self.raw;
        WatchPlanes {
            kind: ON_GPU,
            formats: [r.formats[0], r.formats[1]],
            fds: [r.fds[0], r.fds[1]],
            offsets: [r.offsets[0], r.offsets[1]],
            pitches: [r.pitches[0], r.pitches[1]],
            modifiers: [r.modifiers[0], r.modifiers[1]],
            ..WatchPlanes::sized(r.width as u32, r.height as u32)
        }
    }
}

impl Drop for Decoded {
    fn drop(&mut self) {
        // SAFETY: a picture the library handed out, released once.
        unsafe { (self.release)(&mut self.raw) };
    }
}
