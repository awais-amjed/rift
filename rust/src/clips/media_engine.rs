//! Windows' Media Engine, the player behind the old Edge's `<video>`, which
//! the chat video player ([`super::windows`]) and its poster
//! ([`super::poster_windows`]) both drive.
//!
//! It plays with the decoders Windows has, on the GPU where the driver offers
//! them (through a D3D11 device it is lent), keeps sound and picture together
//! and seeks. In frame server mode it draws nowhere itself: whoever drives it
//! asks whether a new picture is due ([`new_picture`]) and has it drawn into a
//! texture of their own. The file is read where it lies in memory, through a
//! byte stream over a copy of the bytes.
//!
//! N editions of Windows without the Media Feature Pack have no Media
//! Foundation; [`usable`] says so, and the card offers the file to save.
use crate::api::clips::ClipEventKind;
use std::sync::mpsc::Sender;
use std::sync::{Mutex, OnceLock};
use windows::core::{implement, Interface, BSTR, HSTRING};
use windows::Win32::Foundation::{HMODULE, S_OK};
use windows::Win32::Graphics::Direct3D::{
    D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP, D3D_FEATURE_LEVEL, D3D_FEATURE_LEVEL_10_0,
    D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_11_1,
};
use windows::Win32::Graphics::Direct3D10::ID3D10Multithread;
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
    D3D11_CREATE_DEVICE_VIDEO_SUPPORT, D3D11_SDK_VERSION,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT;
use windows::Win32::Media::MediaFoundation::{
    CLSID_MFMediaEngineClassFactory, IMFAttributes, IMFDXGIDeviceManager, IMFMediaEngine,
    IMFMediaEngineClassFactory, IMFMediaEngineEx, IMFMediaEngineNotify, IMFMediaEngineNotify_Impl,
    MFCreateAttributes, MFCreateDXGIDeviceManager, MFCreateMFByteStreamOnStream, MFStartup,
    MFSTARTUP_FULL, MF_AUDIO_RENDERER_ATTRIBUTE_ENDPOINT_ID, MF_MEDIA_ENGINE_CALLBACK,
    MF_MEDIA_ENGINE_DXGI_MANAGER, MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT, MF_VERSION,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
};
use windows::Win32::UI::Shell::SHCreateMemStream;

/// `MF_MEDIA_ENGINE_EVENT`s a driver acts on.
pub(super) const EVENT_ERROR: u32 = 5;
pub(super) const EVENT_ENDED: u32 = 19;

/// `MF_MEDIA_ENGINE_ERR_DECODE` and `_SRC_NOT_SUPPORTED`: Windows' decoders
/// would not take the file, or nothing here reads it. Windows' H264 decoder
/// takes less than FFmpeg's (no 4:4:4, which some screen recorders make), so
/// the card says to save it rather than that it is broken.
const ERR_DECODE: usize = 3;
const ERR_SRC_NOT_SUPPORTED: usize = 4;
/// HRESULTs that mean Windows has no decoder or reader for what the file
/// holds: `MF_E_TOPO_CODEC_NOT_FOUND`, `MF_E_UNSUPPORTED_BYTESTREAM_TYPE`,
/// `MF_E_INVALIDMEDIATYPE`, `MF_E_UNSUPPORTED_FORMAT`.
const MISSING: [u32; 4] = [0xC00D_5212, 0xC00D_36C4, 0xC00D_36B4, 0xC00D_5209];

/// What the engine reported, from its own thread.
pub(super) struct Note {
    pub(super) event: u32,
    pub(super) param1: usize,
    pub(super) param2: u32,
}

/// Media Foundation up for the process, once; never shut down, since a
/// poster or a clip may start at any time.
fn startup() -> Result<(), String> {
    static DONE: OnceLock<Result<(), String>> = OnceLock::new();
    DONE.get_or_init(|| {
        // SAFETY: a plain call; balanced by nothing, on purpose (above).
        unsafe { MFStartup(MF_VERSION, MFSTARTUP_FULL) }
            .map_err(|e| format!("Media Foundation is not here: {e}"))
    })
    .clone()
}

/// Whether this Windows has the Media Engine.
pub(super) fn usable() -> bool {
    static USABLE: OnceLock<bool> = OnceLock::new();
    *USABLE.get_or_init(|| {
        let _com = Com::enter();
        let usable = startup().is_ok() && factory().is_ok();
        if !usable {
            log::warn!("Chat videos: this Windows has no Media Engine");
        }
        usable
    })
}

fn factory() -> windows::core::Result<IMFMediaEngineClassFactory> {
    // SAFETY: a plain COM call on a thread with COM up.
    unsafe { CoCreateInstance(&CLSID_MFMediaEngineClassFactory, None, CLSCTX_INPROC_SERVER) }
}

/// COM for this thread while it lives, multithreaded, as Media Foundation
/// wants. A thread already in an apartment keeps it.
pub(super) struct Com(bool);

impl Com {
    pub(super) fn enter() -> Com {
        // SAFETY: balanced in `drop` when it succeeded.
        Com(unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }.is_ok())
    }
}

impl Drop for Com {
    fn drop(&mut self) {
        if self.0 {
            // SAFETY: this thread's own successful CoInitializeEx.
            unsafe { CoUninitialize() };
        }
    }
}

/// A D3D11 device of the engine's own, with video support where the GPU has
/// it, and Windows' software rasteriser where there is no GPU at all.
pub(super) fn own_device() -> Result<ID3D11Device, String> {
    let levels: [D3D_FEATURE_LEVEL; 4] = [
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    ];
    let make = |driver, flags| {
        let mut device = None;
        // SAFETY: plain COM calls; every out-pointer is local.
        unsafe {
            D3D11CreateDevice(
                None,
                driver,
                HMODULE::default(),
                flags,
                Some(&levels),
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                None,
            )
        }
        .ok()
        .and(device)
    };
    let video = D3D11_CREATE_DEVICE_VIDEO_SUPPORT | D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    let device = make(D3D_DRIVER_TYPE_HARDWARE, video)
        .or_else(|| make(D3D_DRIVER_TYPE_HARDWARE, D3D11_CREATE_DEVICE_BGRA_SUPPORT))
        .or_else(|| make(D3D_DRIVER_TYPE_WARP, D3D11_CREATE_DEVICE_BGRA_SUPPORT))
        .ok_or_else(|| "No D3D11 device for the video".to_string())?;
    protect(&device);
    Ok(device)
}

/// The engine calls the device from its own threads, as the runner does
/// from its; the runner's device is protected already.
pub(super) fn protect(device: &ID3D11Device) {
    if let Ok(multithread) = device.cast::<ID3D10Multithread>() {
        // SAFETY: a plain call on a live device.
        let _ = unsafe { multithread.SetMultithreadProtected(true) };
    }
}

/// One Media Engine in frame server mode, its pictures made on [device] in
/// [format], its sound on the output with endpoint id [output] (the system's
/// default when none), and what it reports sent to [notes].
pub(super) struct Engine {
    pub(super) engine: IMFMediaEngine,
    ex: IMFMediaEngineEx,
    _manager: IMFDXGIDeviceManager,
}

impl Engine {
    pub(super) fn new(
        device: &ID3D11Device,
        format: DXGI_FORMAT,
        output: Option<&str>,
        notes: Sender<Note>,
    ) -> Result<Engine, String> {
        startup()?;
        fn fail(what: &'static str) -> impl Fn(windows::core::Error) -> String {
            move |e| format!("{what}: {e}")
        }
        // SAFETY: plain COM calls on live objects; every out-pointer is local.
        unsafe {
            let mut token = 0u32;
            let mut manager: Option<IMFDXGIDeviceManager> = None;
            MFCreateDXGIDeviceManager(&mut token, &mut manager)
                .map_err(fail("No DXGI device manager"))?;
            let manager = manager.ok_or("No DXGI device manager")?;
            manager
                .ResetDevice(device, token)
                .map_err(fail("The video's device was refused"))?;

            let mut attributes: Option<IMFAttributes> = None;
            MFCreateAttributes(&mut attributes, 4).map_err(fail("No attributes"))?;
            let attributes = attributes.ok_or("No attributes")?;
            let notify: IMFMediaEngineNotify = Notify {
                notes: Mutex::new(notes),
            }
            .into();
            attributes
                .SetUnknown(&MF_MEDIA_ENGINE_CALLBACK, &notify)
                .map_err(fail("No callback"))?;
            attributes
                .SetUnknown(&MF_MEDIA_ENGINE_DXGI_MANAGER, &manager)
                .map_err(fail("No device manager"))?;
            attributes
                .SetUINT32(&MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT, format.0 as u32)
                .map_err(fail("No output format"))?;
            if let Some(output) = output.filter(|o| !o.is_empty()) {
                // The audio renderer's own attribute, which the engine passes
                // on to it; an id it does not know is the default's.
                let _ = attributes.SetString(
                    &MF_AUDIO_RENDERER_ATTRIBUTE_ENDPOINT_ID,
                    &HSTRING::from(output),
                );
            }
            let engine = factory()
                .and_then(|f| f.CreateInstance(0, &attributes))
                .map_err(fail("No Media Engine"))?;
            let ex: IMFMediaEngineEx = engine.cast().map_err(fail("An old Media Engine"))?;
            Ok(Engine {
                engine,
                ex,
                _manager: manager,
            })
        }
    }

    /// Starts reading [bytes], a whole file, which it copies: the caller's
    /// may go once this returns.
    pub(super) fn load(&self, bytes: &[u8]) -> Result<(), String> {
        if u32::try_from(bytes.len()).is_err() {
            return Err("The video is too big to play".to_string());
        }
        // SAFETY: plain COM calls; the stream copies the bytes.
        unsafe {
            let stream = SHCreateMemStream(Some(bytes)).ok_or("No memory for the video")?;
            let byte_stream = MFCreateMFByteStreamOnStream(&stream)
                .map_err(|e| format!("No byte stream: {e}"))?;
            let _ = self.engine.SetAutoPlay(false);
            self.ex
                .SetSourceFromByteStream(&byte_stream, &BSTR::from(name_for(bytes)))
                .map_err(|e| format!("The video would not open: {e}"))
        }
    }

    /// Whether a new picture is due, which [Engine::engine]'s
    /// `TransferVideoFrame` then draws. The wrapper reads S_FALSE, "nothing
    /// new", as success too, so the call is made raw.
    pub(super) fn new_picture(&self) -> bool {
        let mut pts = 0i64;
        // SAFETY: the method's own slot on a live engine, with a local out.
        let hr = unsafe {
            (Interface::vtable(&self.engine).OnVideoStreamTick)(self.engine.as_raw(), &mut pts)
        };
        hr == S_OK
    }

    /// The picture's stored size, and its size as shown: wider or narrower
    /// where its pixels are not square.
    pub(super) fn sizes(&self) -> Option<((u32, u32), (u32, u32))> {
        let (mut w, mut h, mut ax, mut ay) = (0u32, 0u32, 0u32, 0u32);
        // SAFETY: plain calls on a live engine, into locals.
        unsafe {
            self.engine
                .GetNativeVideoSize(Some(&mut w), Some(&mut h))
                .ok()?;
            let _ = self
                .engine
                .GetVideoAspectRatio(Some(&mut ax), Some(&mut ay));
        }
        if w == 0 || h == 0 {
            return None;
        }
        let shown_w = if ax > 0 && ay > 0 {
            ((h as u64 * ax as u64 + ay as u64 / 2) / ay as u64) as u32
        } else {
            w
        };
        Some(((w, h), (shown_w.max(1), h)))
    }

    pub(super) fn has_video(&self) -> bool {
        // SAFETY: a plain call on a live engine.
        unsafe { self.engine.HasVideo() }.as_bool()
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        // SAFETY: a plain call on a live engine; it lets go of the callback
        // and the source, and stops calling back.
        let _ = unsafe { self.engine.Shutdown() };
    }
}

/// What a failure reported by [EVENT_ERROR] means for the card: a file
/// Windows has nothing to play with, or something else.
pub(super) fn failure(param1: usize, param2: u32) -> (ClipEventKind, String) {
    let missing =
        param1 == ERR_DECODE || param1 == ERR_SRC_NOT_SUPPORTED || MISSING.contains(&param2);
    let reason = format!("Media Engine error {param1}, {param2:#010x}");
    if missing {
        (ClipEventKind::CannotDecode, reason)
    } else {
        (ClipEventKind::Failed, reason)
    }
}

/// A file name for [bytes], whose extension tells Windows which reader to
/// try first: a byte stream has no name of its own.
pub(super) fn name_for(bytes: &[u8]) -> &'static str {
    if bytes.len() >= 12 && &bytes[4..8] == b"ftyp" {
        if &bytes[8..12] == b"qt  " {
            "clip.mov"
        } else {
            "clip.mp4"
        }
    } else if bytes.starts_with(&[0x1a, 0x45, 0xdf, 0xa3]) {
        "clip.webm"
    } else {
        "clip.mp4"
    }
}

#[implement(IMFMediaEngineNotify)]
struct Notify {
    notes: Mutex<Sender<Note>>,
}

impl IMFMediaEngineNotify_Impl for Notify_Impl {
    fn EventNotify(&self, event: u32, param1: usize, param2: u32) -> windows::core::Result<()> {
        let _ = self
            .notes
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .send(Note {
                event,
                param1,
                param2,
            });
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_the_container() {
        let mut mp4 = vec![0, 0, 0, 24];
        mp4.extend_from_slice(b"ftypisom");
        assert_eq!(name_for(&mp4), "clip.mp4");
        let mut mov = vec![0, 0, 0, 20];
        mov.extend_from_slice(b"ftypqt  ");
        assert_eq!(name_for(&mov), "clip.mov");
        assert_eq!(name_for(&[0x1a, 0x45, 0xdf, 0xa3, 1]), "clip.webm");
        assert_eq!(name_for(b"nothing"), "clip.mp4");
    }

    #[test]
    fn a_missing_decoder_is_cannot_decode() {
        assert!(matches!(
            failure(3, 0xC00D_5212).0,
            ClipEventKind::CannotDecode
        ));
        assert!(matches!(failure(4, 0).0, ClipEventKind::CannotDecode));
        assert!(matches!(
            failure(3, 0x8000_4005).0,
            ClipEventKind::CannotDecode
        ));
        // MF_MEDIA_ENGINE_ERR_NETWORK, which a file in memory should never
        // give, is something else.
        assert!(matches!(failure(2, 0x8000_4005).0, ClipEventKind::Failed));
    }
}
