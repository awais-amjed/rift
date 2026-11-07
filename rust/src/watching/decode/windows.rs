//! Windows: FFmpeg's D3D11 video decoder, in Rift's FFmpeg library
//! (`native/ffenc/ffdec.h`), on the runner's own device: the one it draws
//! watched shares with, on the adapter Flutter draws with. Each picture leaves
//! as a slice of the decoder's texture array, which the runner draws where it
//! lies (`windows/runner/stream_draw.cpp`).
//!
//! The device never passes through Dart: the runner exports
//! `rift_stream_d3d11_device`, which answers it with a reference added, and the
//! decoder takes it when it opens. A device lost meanwhile is still a live
//! object whose calls fail, so no address outlives what it names.

use super::super::frames::{Picture, WatchPlanes, IN_D3D11};
use super::Codec;
use crate::screenshare::encoder::ffmpeg::{library, symbol};
use std::ffi::{c_char, c_void, CStr};
use std::fmt;
use std::sync::OnceLock;
use windows::core::{Interface, GUID};
use windows::Win32::Foundation::{HMODULE, LUID};
use windows::Win32::Graphics::Direct3D::{
    D3D_DRIVER_TYPE_UNKNOWN, D3D_FEATURE_LEVEL, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_11_1,
};
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, ID3D11VideoDevice, D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
    D3D11_SDK_VERSION,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_NV12;
use windows::Win32::Graphics::Dxgi::{CreateDXGIFactory1, IDXGIDevice, IDXGIFactory1};

/// FFmpeg's AVERROR(ENOSYS): the GPU cannot decode this stream. Windows'
/// ENOSYS is 40, where Linux's is 38.
const NO_GPU_DECODER: i32 = -40;

/// `RiftFfdecApi`'s D3D11VA.
const D3D11VA: i32 = 2;

/// `RiftFfdecMemory`'s D3D11.
const MEMORY_D3D11: i32 = 2;

/// D3D11's decoder profiles FFmpeg's hwaccels take (dxva2.c), 8-bit only:
/// H264 as DXVA2_ModeH264_E and _F and Intel's ClearVideo form of E, and VP9
/// profile 0.
const H264_PROFILES: [GUID; 3] = [
    GUID::from_u128(0x1b81be68_a0c7_11d3_b984_00c04f2e73c5),
    GUID::from_u128(0x1b81be69_a0c7_11d3_b984_00c04f2e73c5),
    GUID::from_u128(0x604f8e68_4951_4c54_88fe_abd25c15b3d6),
];
/// D3D11_DECODER_PROFILE_HEVC_VLD_MAIN: eight bits, all a share sends.
const H265_PROFILES: [GUID; 1] = [GUID::from_u128(0x5b11d51b_2f4c_4452_bcc3_09f2a1160cc0)];
const VP9_PROFILES: [GUID; 1] = [GUID::from_u128(0x463707f8_a1d0_4585_876d_83aa6d60b89e)];

#[repr(C)]
struct Config {
    codec: i32,
    device: *const c_char,
    api: i32,
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

/// The GPU watched shares decode on: adapter 0, the one Flutter's ANGLE takes
/// (Rift sets no GPU preference), and what its video decoder offers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Gpu {
    /// The adapter's LUID, which the runner's own adapter must be.
    luid: i64,
    name: String,
    h264: bool,
    h265: bool,
    vp9: bool,
}

impl fmt::Display for Gpu {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}, through D3D11", self.name)
    }
}

impl Gpu {
    /// From the decoder profiles the adapter lists, each with NV12 out.
    fn from_profiles(luid: i64, name: String, profiles: &[GUID]) -> Gpu {
        let has = |wanted: &[GUID]| profiles.iter().any(|p| wanted.contains(p));
        Gpu {
            luid,
            name,
            h264: has(&H264_PROFILES),
            h265: has(&H265_PROFILES),
            vp9: has(&VP9_PROFILES),
        }
    }

    /// Whether the runner can draw what this GPU decodes: its device is on
    /// this adapter. Asked at each watch, of the device the runner has then,
    /// since adapter 0 may have moved since start (a GPU switched in Hybrid
    /// mode): the runner's device is on the adapter Flutter draws with, which
    /// is not always the one checked here.
    pub(crate) fn drawn_by_runner(&self) -> bool {
        self.drawn_on(runner_device().as_ref())
    }

    fn drawn_on(&self, device: Option<&ID3D11Device>) -> bool {
        let Some(device) = device else {
            log::warn!("watching: the window has no GPU device");
            return false;
        };
        // SAFETY: plain COM calls on a live device; the adapter's description
        // is written into a local.
        let desc = unsafe {
            device
                .cast::<IDXGIDevice>()
                .and_then(|dxgi| dxgi.GetAdapter())
                .and_then(|adapter| adapter.GetDesc())
        };
        match desc {
            Ok(desc) if luid_of(desc.AdapterLuid) == self.luid => true,
            Ok(desc) => {
                let len = desc.Description.iter().position(|&c| c == 0).unwrap_or(128);
                log::warn!(
                    "watching: the window draws on {}, not {}, which decodes",
                    String::from_utf16_lossy(&desc.Description[..len]),
                    self.name
                );
                false
            }
            Err(e) => {
                log::warn!("watching: the window's adapter: {e}");
                false
            }
        }
    }

    /// Whether the GPU decodes [codec]: asked of its decoder at start, so
    /// always an answer. VP8 never: no GPU offers it through D3D11, and
    /// FFmpeg has no hwaccel for it.
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn decodes(&self, codec: Codec) -> Option<bool> {
        Some(match codec {
            Codec::H264 => self.h264,
            Codec::H265 => self.h265,
            Codec::Vp9 => self.vp9,
            Codec::Vp8 => false,
        })
    }
}

/// A LUID as one number, to compare.
fn luid_of(luid: LUID) -> i64 {
    (i64::from(luid.HighPart) << 32) | i64::from(luid.LowPart)
}

/// Adapter 0 and its video decoder's profiles; an error when it has none Rift
/// decodes, or the library is not there to decode with.
pub(super) fn device() -> Result<Gpu, String> {
    let gpu = adapter_zero().map_err(|e| format!("no D3D11 video decoder: {e}"))?;
    if !gpu.h264 && !gpu.vp9 {
        return Err(format!("{} decodes neither H264 nor VP9", gpu.name));
    }
    api()?;
    Ok(gpu)
}

fn adapter_zero() -> windows::core::Result<Gpu> {
    // SAFETY: plain COM calls; every out-pointer is local.
    unsafe {
        let factory: IDXGIFactory1 = CreateDXGIFactory1()?;
        let adapter = factory.EnumAdapters1(0)?;
        let desc = adapter.GetDesc1()?;
        let luid = luid_of(desc.AdapterLuid);
        let len = desc.Description.iter().position(|&c| c == 0).unwrap_or(128);
        let name = String::from_utf16_lossy(&desc.Description[..len]);
        let levels: [D3D_FEATURE_LEVEL; 2] = [D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0];
        let mut device = None;
        D3D11CreateDevice(
            &adapter,
            D3D_DRIVER_TYPE_UNKNOWN,
            HMODULE::default(),
            D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
            Some(&levels),
            D3D11_SDK_VERSION,
            Some(&mut device),
            None,
            None,
        )?;
        let device: ID3D11Device =
            device.ok_or_else(|| windows::core::Error::from(windows::Win32::Foundation::E_FAIL))?;
        let video: ID3D11VideoDevice = device.cast()?;
        let mut profiles = Vec::new();
        for i in 0..video.GetVideoDecoderProfileCount() {
            let Ok(profile) = video.GetVideoDecoderProfile(i) else {
                continue;
            };
            if video
                .CheckVideoDecoderFormat(&profile, DXGI_FORMAT_NV12)
                .is_ok_and(|ok| ok.as_bool())
            {
                profiles.push(profile);
            }
        }
        Ok(Gpu::from_profiles(luid, name, &profiles))
    }
}

/// The runner's device, from its `rift_stream_d3d11_device` export, with the
/// reference it added; none when the export or the device is missing (an old
/// runner, the test program, or a device lost).
fn runner_device() -> Option<ID3D11Device> {
    #[cfg(test)]
    {
        tests::device_in_place()
    }
    #[cfg(not(test))]
    {
        use windows::core::s;
        use windows::Win32::System::LibraryLoader::{GetModuleHandleW, GetProcAddress};
        // SAFETY: the export, when the exe has it, is the runner's, with this
        // type (stream_texture.h); it answers a device with a reference added
        // for the caller, which `from_raw` takes over.
        unsafe {
            let exe = GetModuleHandleW(None).ok()?;
            let export = GetProcAddress(exe, s!("rift_stream_d3d11_device"))?;
            let export: unsafe extern "C" fn() -> *mut c_void = std::mem::transmute(export);
            let raw = export();
            (!raw.is_null()).then(|| ID3D11Device::from_raw(raw))
        }
    }
}

/// One share's decoder, used on its one thread.
pub(crate) struct Decoder {
    api: &'static Api,
    raw: *mut c_void,
    /// The runner's device it decodes on, asked whether it was removed when
    /// a picture fails.
    device: ID3D11Device,
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
    pub(crate) fn open(codec: Codec, _gpu: &Gpu) -> Result<Decoder, String> {
        // FFmpeg takes a reference of its own, let go when it closes.
        let device = runner_device().ok_or("the window has no GPU device")?;
        let api = api()?;
        let config = Config {
            codec: match codec {
                Codec::H264 => 1,
                Codec::Vp8 => 2,
                Codec::Vp9 => 3,
                Codec::H265 => 4,
            },
            device: std::ptr::null(),
            api: D3D11VA,
            d3d11_device: device.as_raw(),
        };
        let mut error = [0 as c_char; 256];
        // SAFETY: the config, the device it names and the error buffer outlive
        // the call, which writes at most `error.len()` bytes into it.
        let raw = unsafe { (api.open)(&config, error.as_mut_ptr(), error.len()) };
        if raw.is_null() {
            // SAFETY: the library wrote a NUL-terminated reason into it.
            let reason = unsafe { CStr::from_ptr(error.as_ptr()) }.to_string_lossy();
            return Err(format!("the GPU decoder did not open: {reason}"));
        }
        Ok(Decoder { api, raw, device })
    }

    /// Whether the device it decodes on was removed, a reset or a driver
    /// update: no picture decodes on it again. The runner lets it go the next
    /// time it is asked for one (`stream_device.cpp`).
    pub(crate) fn device_lost(&self) -> bool {
        // SAFETY: a plain call on a live device.
        unsafe { self.device.GetDeviceRemovedReason() }.is_err()
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
                1 if raw.memory == MEMORY_D3D11 => pictures.push(Decoded { raw, api: self.api }),
                1 => {
                    // SAFETY: a picture the library handed out, released once.
                    unsafe { (self.api.release)(&mut raw) };
                    return Err(DecodeError::NoGpuDecoder);
                }
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

/// A picture decoded on the GPU, holding its slice until it goes.
pub(crate) struct Decoded {
    raw: RawPicture,
    api: &'static Api,
}

// SAFETY: the picture is a reference to a slice of the decoder's array, which
// FFmpeg lets go of from any thread (`rift_ffdec_release`), and the runner
// draws from under the device's lock while it is lent.
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
            kind: IN_D3D11,
            matrix: r.matrix as u32,
            full_range: r.full_range as u32,
            texture: r.d3d11_texture,
            slice: r.d3d11_slice as u32,
            ..WatchPlanes::sized(r.width as u32, r.height as u32)
        }
    }
}

impl Drop for Decoded {
    fn drop(&mut self) {
        // SAFETY: a picture the library handed out, released once.
        unsafe { (self.api.release)(&mut self.raw) };
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::sync::Mutex;

    /// The device a test puts in the runner's place: a test binary exports
    /// nothing.
    static IN_PLACE: Mutex<Option<ID3D11Device>> = Mutex::new(None);

    pub(crate) fn put_device_in_place(device: Option<ID3D11Device>) {
        *IN_PLACE.lock().unwrap_or_else(|e| e.into_inner()) = device;
    }

    pub(super) fn device_in_place() -> Option<ID3D11Device> {
        IN_PLACE.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// A device made on adapter 0 the way the runner makes its own
    /// (`stream_draw.cpp`, `MakeDevice`), in the runner's place while this
    /// lives.
    pub(crate) struct RunnerDeviceInPlace {
        device: ID3D11Device,
        before: u32,
    }

    impl RunnerDeviceInPlace {
        pub(crate) fn new() -> RunnerDeviceInPlace {
            use windows::Win32::Graphics::Direct3D10::ID3D10Multithread;
            use windows::Win32::Graphics::Direct3D11::D3D11_CREATE_DEVICE_BGRA_SUPPORT;
            // SAFETY: plain COM calls; every out-pointer is local.
            let device = unsafe {
                let factory: IDXGIFactory1 = CreateDXGIFactory1().expect("DXGI");
                let adapter = factory.EnumAdapters1(0).expect("adapter 0");
                let levels = [D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0];
                let mut device = None;
                D3D11CreateDevice(
                    &adapter,
                    D3D_DRIVER_TYPE_UNKNOWN,
                    HMODULE::default(),
                    D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
                    Some(&levels),
                    D3D11_SDK_VERSION,
                    Some(&mut device),
                    None,
                    None,
                )
                .expect("a video device on adapter 0");
                let device: ID3D11Device = device.expect("a device");
                let multithread: ID3D10Multithread = device.cast().expect("multithread");
                let _ = multithread.SetMultithreadProtected(true);
                device
            };
            let before = references(&device);
            put_device_in_place(Some(device.clone()));
            RunnerDeviceInPlace {
                device,
                before: before + 1,
            }
        }

        /// Every reference the decoders took is handed back, within a few
        /// seconds: a decoding thread ends at its next frame or wait.
        pub(crate) fn assert_all_handed_back(&self) {
            let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
            while references(&self.device) != self.before && std::time::Instant::now() < deadline {
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            assert_eq!(
                references(&self.device),
                self.before,
                "references to the runner's device the decoders kept"
            );
        }
    }

    impl Drop for RunnerDeviceInPlace {
        fn drop(&mut self) {
            put_device_in_place(None);
        }
    }

    fn references(device: &ID3D11Device) -> u32 {
        // SAFETY: an AddRef and its Release on a live interface.
        unsafe {
            let unknown = &device.vtable().base__;
            (unknown.AddRef)(device.as_raw());
            (unknown.Release)(device.as_raw())
        }
    }

    /// A lent D3D11 picture's array is NV12, holds its slice, and is at least
    /// the picture's size.
    pub(crate) fn slice_holds(planes: &WatchPlanes) -> bool {
        use windows::Win32::Graphics::Direct3D11::{ID3D11Texture2D, D3D11_TEXTURE2D_DESC};
        // SAFETY: the texture is the lent picture's, alive while it is lent;
        // borrowed, not released.
        let Some(texture) = (unsafe { ID3D11Texture2D::from_raw_borrowed(&planes.texture) }) else {
            return false;
        };
        let mut desc = D3D11_TEXTURE2D_DESC::default();
        // SAFETY: a live texture describing itself into a local.
        unsafe { texture.GetDesc(&mut desc) };
        desc.Format == DXGI_FORMAT_NV12
            && planes.slice < desc.ArraySize
            && desc.Width >= planes.width
            && desc.Height >= planes.height
    }

    fn gpu(profiles: &[GUID]) -> Gpu {
        Gpu::from_profiles(1, "a GPU".to_string(), profiles)
    }

    #[test]
    fn decodes_what_its_profiles_say() {
        let both = gpu(&[H264_PROFILES[0], VP9_PROFILES[0]]);
        assert_eq!(both.decodes(Codec::H264), Some(true));
        assert_eq!(both.decodes(Codec::Vp9), Some(true));
        let intel_h264 = gpu(&[H264_PROFILES[2]]);
        assert_eq!(intel_h264.decodes(Codec::H264), Some(true));
        assert_eq!(intel_h264.decodes(Codec::Vp9), Some(false));
        // HEVC Main and VP9 profile 2 (10-bit) only.
        let other = gpu(&[
            GUID::from_u128(0x5b11d51b_2f4c_4452_bcc3_09f2a1160cc0),
            GUID::from_u128(0xa4c749ef_6ecf_48aa_8448_50a7a1165ff7),
        ]);
        assert_eq!(other.decodes(Codec::H264), Some(false));
        assert_eq!(other.decodes(Codec::Vp9), Some(false));
    }

    #[test]
    fn vp8_is_never_decoded_on_the_gpu() {
        let both = gpu(&[H264_PROFILES[0], VP9_PROFILES[0]]);
        assert_eq!(both.decodes(Codec::Vp8), Some(false));
    }

    /// A device on adapter 0, made the way the runner makes its own.
    fn device_on_adapter_zero() -> (ID3D11Device, i64) {
        // SAFETY: plain COM calls; every out-pointer is local.
        unsafe {
            let factory: IDXGIFactory1 = CreateDXGIFactory1().expect("DXGI");
            let adapter = factory.EnumAdapters1(0).expect("adapter 0");
            let luid = luid_of(adapter.GetDesc1().expect("its description").AdapterLuid);
            let levels = [D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0];
            let mut device = None;
            D3D11CreateDevice(
                &adapter,
                D3D_DRIVER_TYPE_UNKNOWN,
                HMODULE::default(),
                D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
                Some(&levels),
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                None,
            )
            .expect("a video device on adapter 0");
            (device.expect("a device"), luid)
        }
    }

    #[test]
    fn the_runner_draws_what_its_own_adapter_decoded() {
        let (device, luid) = device_on_adapter_zero();
        let decoded_there = Gpu::from_profiles(luid, "a GPU".to_string(), &[H264_PROFILES[0]]);
        assert!(decoded_there.drawn_on(Some(&device)));
    }

    #[test]
    fn the_runner_refuses_what_another_adapter_decoded() {
        // Rust checked one adapter at start; the runner's device is on
        // another, as when the adapters' order moved before the first watch.
        let (device, luid) = device_on_adapter_zero();
        let decoded_elsewhere =
            Gpu::from_profiles(luid ^ 1, "another GPU".to_string(), &[H264_PROFILES[0]]);
        assert!(!decoded_elsewhere.drawn_on(Some(&device)));
    }

    #[test]
    fn the_runner_draws_nothing_with_no_device() {
        let (_, luid) = device_on_adapter_zero();
        let gpu = Gpu::from_profiles(luid, "a GPU".to_string(), &[H264_PROFILES[0]]);
        assert!(!gpu.drawn_on(None));
    }

    #[test]
    fn a_window_with_no_gpu_device_opens_no_decoder() {
        put_device_in_place(None);
        let gpu = gpu(&[H264_PROFILES[0]]);
        match Decoder::open(Codec::H264, &gpu) {
            Ok(_) => panic!("opened with no device"),
            Err(why) => assert_eq!(why, "the window has no GPU device"),
        }
    }
}
