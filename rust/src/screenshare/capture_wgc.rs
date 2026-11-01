//! A Windows share on Rift's own Windows Graphics Capture session
//! (`docs/gpu-codecs/STEP1_WINDOWS.md`): each picture stays on the GPU and goes
//! to NVENC on the same device, drawn into NV12 by ffenc. When any of it refuses,
//! the share runs on libwebrtc's capturer as before, with no second picker, since
//! Rift's own list chose the source.
//!
//! Read from OBS's `libobs-winrt/winrt-capture.cpp`, FFmpeg's
//! `vsrc_gfxcapture_winrt.cpp` and Sunshine's `display_wgc.cpp`. As FFmpeg and
//! Sunshine do, the frame pool is free-threaded, so nothing here needs a message
//! loop. As FFmpeg does, `graphicscapture.dll` is kept loaded, since letting it
//! unload with WinRT's teardown crashes.
use super::capture::{self, CaptureRequest, Command, Feed, Progress, Recapture, SharedWindow};
use super::encoder::{self, GpuCodec};
use super::frames::now_us;
use super::gpu_feed::{GpuFeed, Picture};
use super::latest::{self, Putter, Taker};
use super::resolution::Size;
use super::sources;
use crate::api::screenshare::types::{ScreenshareEvent, VideoCodec};
use livekit::webrtc::desktop_capturer::{
    CaptureSource as Source, DesktopCaptureSourceType, DesktopCapturer,
};
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::thread;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::UnboundedSender;
use windows::core::{factory, Interface, Ref, BOOL, HSTRING};
use windows::Foundation::{TimeSpan, TypedEventHandler};
use windows::Graphics::Capture::{
    Direct3D11CaptureFrame, Direct3D11CaptureFramePool, GraphicsCaptureItem, GraphicsCaptureSession,
};
use windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
use windows::Graphics::DirectX::DirectXPixelFormat;
use windows::Graphics::SizeInt32;
use windows::Win32::Foundation::{HMODULE, HWND, LPARAM, RECT};
use windows::Win32::Graphics::Direct3D::{D3D_DRIVER_TYPE_UNKNOWN, D3D_FEATURE_LEVEL};
use windows::Win32::Graphics::Direct3D10::ID3D10Multithread;
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, ID3D11Texture2D, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
    D3D11_SDK_VERSION, D3D11_TEXTURE2D_DESC,
};
use windows::Win32::Graphics::Dxgi::{
    CreateDXGIFactory1, IDXGIAdapter1, IDXGIDevice, IDXGIFactory1, DXGI_ADAPTER_FLAG_SOFTWARE,
};
use windows::Win32::Graphics::Gdi::{
    EnumDisplayDevicesW, EnumDisplayMonitors, GetMonitorInfoW, DISPLAY_DEVICEW, HDC, HMONITOR,
    MONITORINFO, MONITORINFOEXW,
};
use windows::Win32::System::LibraryLoader::{LoadLibraryExW, LOAD_LIBRARY_SEARCH_SYSTEM32};
use windows::Win32::System::WinRT::Direct3D11::{
    CreateDirect3D11DeviceFromDXGIDevice, IDirect3DDxgiInterfaceAccess,
};
use windows::Win32::System::WinRT::Graphics::Capture::IGraphicsCaptureItemInterop;
use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};

/// How often the capture thread looks for a stop, an ended window or a new rate.
/// The pictures themselves never wait on it.
const POLL: Duration = Duration::from_millis(50);

/// How often the processing thread looks for a new feed on a still screen.
const QUIET: Duration = Duration::from_millis(100);

/// The frame pool's buffers. A picture can wait in this module's mailbox, wait for
/// the encoder and be drawn by it at once, and the pool needs one to write into.
const POOL_BUFFERS: i32 = 4;

/// One picture from the frame pool. The buffer goes back when the last holder
/// drops it.
pub(crate) struct WgcPicture {
    frame: Direct3D11CaptureFrame,
    texture: ID3D11Texture2D,
    size: Size,
}

// SAFETY: the frame is free-threaded, and only `gpu-encoder` reads the texture,
// through a device made multithread-protected.
unsafe impl Send for WgcPicture {}
unsafe impl Sync for WgcPicture {}

impl WgcPicture {
    pub(crate) fn size(&self) -> Size {
        self.size
    }

    /// The `ID3D11Texture2D`, alive as long as this picture is.
    pub(crate) fn texture(&self) -> *mut c_void {
        self.texture.as_raw()
    }
}

impl Drop for WgcPicture {
    fn drop(&mut self) {
        let _ = self.frame.Close();
    }
}

/// The running share's device, on which its pictures are and on which its encoder
/// has to open. Held only for a share's life, so what a share opened on the GPU
/// goes with it.
static SHARE_DEVICE: Mutex<Option<SharedDevice>> = Mutex::new(None);

struct SharedDevice(ID3D11Device);

// SAFETY: a D3D11 device is free-threaded; only its immediate context is not, and
// this device's is multithread-protected and used on `gpu-encoder` alone.
unsafe impl Send for SharedDevice {}

/// The device an encoder opening now should take pictures on, if any.
pub(crate) fn share_device() -> Option<ID3D11Device> {
    SHARE_DEVICE
        .lock()
        .unwrap()
        .as_ref()
        .map(|held| held.0.clone())
}

/// Clears [`SHARE_DEVICE`] however the share ends.
struct DeviceHeld;

impl Drop for DeviceHeld {
    fn drop(&mut self) {
        *SHARE_DEVICE.lock().unwrap() = None;
    }
}

/// How a share went on Rift's own capture.
pub(super) enum Handoff {
    /// It ran, and is over.
    Done,
    /// Not here, or not any more: libwebrtc's capturer takes the request.
    Fallback(CaptureRequest),
}

/// Whether a share goes on Rift's own capture: with the switch on, in a codec the
/// GPU makes, to an encoder that takes the picture on the GPU. A screen also needs
/// Windows Graphics Capture to be how screens are captured here: on Windows 10
/// they stay on DXGI, which draws no border (`sources::options`). Windows there
/// have no other way, so they come here too.
fn takes_rifts_capture(
    gpu_capture: bool,
    codec: VideoCodec,
    encoder_takes_textures: bool,
    source_type: DesktopCaptureSourceType,
    screens_on_wgc: bool,
) -> bool {
    gpu_capture
        && GpuCodec::for_share(codec).is_some()
        && encoder_takes_textures
        && (source_type != DesktopCaptureSourceType::Screen || screens_on_wgc)
}

/// Which pictures go on, at the share's rate. Windows only sends a picture when
/// the source changes, at a refresh of the screen, so what arrives seldom lines up
/// with the rate: half a picture's time of slack keeps a source just above the
/// share's rate from beating against it (a 62 Hz picture at 60 fps came through at
/// 50, Nov 1 2026), and the time it is due moves on by a whole picture, so the
/// average is still the share's.
struct Pacer {
    due: Option<Instant>,
}

impl Pacer {
    fn new() -> Self {
        Self { due: None }
    }

    fn admits(&mut self, now: Instant, fps: u32) -> bool {
        let interval = Duration::from_secs_f64(1.0 / f64::from(fps.max(1)));
        match self.due {
            Some(due) if now + interval / 2 < due => false,
            due => {
                let next = due.unwrap_or(now) + interval;
                // Never from long ago, or a pause would be made up in a burst.
                self.due = Some(if next <= now { now + interval } else { next });
                true
            }
        }
    }
}

/// What the frame pool's thread and the capture thread share.
struct Flow {
    /// `None` once the share is over, which ends the processing thread.
    pictures: Mutex<Option<Putter<WgcPicture>>>,
    first: Mutex<Option<UnboundedSender<Progress>>>,
    /// The item closed.
    lost: AtomicBool,
    /// A picture has come in.
    arrived: AtomicBool,
    fps: Arc<AtomicU32>,
    pacer: Mutex<Pacer>,
}

/// One running session, undone on drop.
struct Session {
    pool: Direct3D11CaptureFramePool,
    session: GraphicsCaptureSession,
    item: GraphicsCaptureItem,
    frame_arrived: i64,
    closed: i64,
}

impl Drop for Session {
    fn drop(&mut self) {
        // In the order FFmpeg's wgc_stop_capture_session takes: no more calls
        // from either event first. An event already running holds its own
        // references, and sees the pool closed as a failure it ignores.
        let _ = self.item.RemoveClosed(self.closed);
        let _ = self.pool.RemoveFrameArrived(self.frame_arrived);
        let _ = self.session.Close();
        let _ = self.pool.Close();
    }
}

/// The session's WinRT device, as the frame pool's event keeps it.
struct FreeThreaded(IDirect3DDevice);

// SAFETY: the WinRT device is only a handle on a multithread-protected D3D11
// device, and is passed to `Recreate` alone, as FFmpeg's and OBS's are.
unsafe impl Send for FreeThreaded {}

/// What a session is on.
#[derive(Clone, Copy)]
enum Target {
    Window(u64),
    Screen(HMONITOR),
}

fn item_for(target: Target) -> windows::core::Result<GraphicsCaptureItem> {
    let interop = factory::<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()?;
    // SAFETY: a closed window or gone monitor only makes the call fail.
    unsafe {
        match target {
            Target::Window(id) => interop.CreateForWindow(HWND(id as isize as *mut c_void)),
            Target::Screen(monitor) => interop.CreateForMonitor(monitor),
        }
    }
}

/// The interval Windows is asked for at `fps`, in 100 ns ticks: half a picture's
/// time, so that what comes at the screen's refreshes can still make the rate
/// (asked for a picture's whole time, a 165 Hz screen gives every third refresh or
/// later, 55 fps at best of 60). [`Pacer`] takes it down to the rate.
fn update_interval(fps: u32) -> TimeSpan {
    TimeSpan {
        Duration: 10_000_000 / i64::from(fps.max(1)) / 2,
    }
}

fn open_session(
    device: &IDirect3DDevice,
    target: Target,
    cursor: bool,
    flow: &Arc<Flow>,
) -> windows::core::Result<Session> {
    let item = item_for(target)?;
    let size = item.Size()?;
    let pool = Direct3D11CaptureFramePool::CreateFreeThreaded(
        device,
        DirectXPixelFormat::B8G8R8A8UIntNormalized,
        POOL_BUFFERS,
        size,
    )?;
    let session = pool.CreateCaptureSession(&item)?;
    // Each of these is missing on some Windows, and a share goes on without it:
    // the cursor from Windows 10 2004, the border's switch from build 20348, the
    // rate from Windows 11.
    let _ = session.SetIsCursorCaptureEnabled(cursor);
    let _ = session.SetIsBorderRequired(false);
    #[cfg(test)]
    let interval_off = std::env::var_os("RIFT_WGC_NO_MIN_INTERVAL").is_some();
    #[cfg(not(test))]
    let interval_off = false;
    if !interval_off {
        let _ = session.SetMinUpdateInterval(update_interval(flow.fps.load(Ordering::Relaxed)));
    }

    let closed = {
        let flow = flow.clone();
        item.Closed(&TypedEventHandler::new(
            move |_: Ref<GraphicsCaptureItem>, _: Ref<windows::core::IInspectable>| {
                flow.lost.store(true, Ordering::Relaxed);
                Ok(())
            },
        ))?
    };
    let frame_arrived = {
        let flow = flow.clone();
        let device = FreeThreaded(device.clone());
        let pool_size = Mutex::new(size);
        pool.FrameArrived(&TypedEventHandler::new(
            move |pool: Ref<Direct3D11CaptureFramePool>, _: Ref<windows::core::IInspectable>| {
                // A failure here is a pool closing under a late event, or a lost
                // device the encoder reports; nothing may unwind out of a callback.
                let holder = &device;
                if let Some(pool) = pool.as_ref() {
                    let _ = picture_arrived(pool, &holder.0, &pool_size, &flow);
                }
                Ok(())
            },
        ))?
    };
    let opened = Session {
        pool,
        session,
        item,
        frame_arrived,
        closed,
    };
    opened.session.StartCapture()?;
    Ok(opened)
}

/// On the frame pool's thread, which must not be held up.
fn picture_arrived(
    pool: &Direct3D11CaptureFramePool,
    device: &IDirect3DDevice,
    pool_size: &Mutex<SizeInt32>,
    flow: &Flow,
) -> windows::core::Result<()> {
    let frame = pool.TryGetNextFrame()?;
    #[cfg(test)]
    arrivals::arrived(Instant::now());
    let content = frame.ContentSize()?;
    let surface = frame.Surface()?;
    let access: IDirect3DDxgiInterfaceAccess = surface.cast()?;
    // SAFETY: the surface is a D3D11 texture on the pool's device.
    let texture: ID3D11Texture2D = unsafe { access.GetInterface()? };
    let mut desc = D3D11_TEXTURE2D_DESC::default();
    // SAFETY: `desc` is written, and nothing else is touched.
    unsafe { texture.GetDesc(&mut desc) };

    // A window resized: this picture is in the old buffers, the new size goes in
    // from the next. OBS and FFmpeg both follow the content size so.
    {
        let mut known = pool_size.lock().unwrap();
        if content.Width > 0
            && content.Height > 0
            && (content.Width != known.Width || content.Height != known.Height)
        {
            pool.Recreate(
                device,
                DirectXPixelFormat::B8G8R8A8UIntNormalized,
                POOL_BUFFERS,
                content,
            )?;
            *known = content;
        }
    }
    let size = Size {
        width: (content.Width.max(0) as u32).min(desc.Width),
        height: (content.Height.max(0) as u32).min(desc.Height),
    };
    // What a window gives as it closes is no picture of anything, as libwebrtc's
    // capturer gave too (`capture::Signals`).
    if size.width < 2 || size.height < 2 {
        return Ok(());
    }
    let fps = flow.fps.load(Ordering::Relaxed);
    if !flow.pacer.lock().unwrap().admits(Instant::now(), fps) {
        return Ok(());
    }
    #[cfg(test)]
    arrivals::kept();
    if let Some(tx) = flow.first.lock().unwrap().take() {
        let _ = tx.send(Progress::FirstFrame(size));
    }
    flow.arrived.store(true, Ordering::Relaxed);
    let picture = WgcPicture {
        frame,
        texture,
        size,
    };
    if let Some(pictures) = &*flow.pictures.lock().unwrap() {
        // The one it replaced goes back to the pool here.
        drop(pictures.put(picture));
    }
    Ok(())
}

/// The adapter of `vendor`, the encoder's (`encoder::takes_textures`), which
/// needs its pictures there whichever GPU draws the screen: Windows Graphics
/// Capture crosses between GPUs itself. Found by its vendor and never by its
/// place in the list, which moved while CS2 ran (Nov 1 2026). A test build
/// takes another vendor from `RIFT_WGC_VENDOR` (hex), to see a mismatch fall back.
fn adapter_of(vendor: u32) -> Option<IDXGIAdapter1> {
    #[cfg(test)]
    let vendor = std::env::var("RIFT_WGC_VENDOR")
        .ok()
        .and_then(|v| u32::from_str_radix(v.trim_start_matches("0x"), 16).ok())
        .unwrap_or(vendor);
    // SAFETY: plain DXGI calls with no pointers kept.
    unsafe {
        let factory: IDXGIFactory1 = CreateDXGIFactory1().ok()?;
        (0..)
            .map_while(|at| factory.EnumAdapters1(at).ok())
            .find(|adapter| {
                adapter.GetDesc1().is_ok_and(|desc| {
                    desc.VendorId == vendor && desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE.0 as u32 == 0
                })
            })
    }
}

/// Test builds only: `RIFT_D3D11_DEBUG=1` opens the device under the D3D
/// debug layer (Windows' Graphics Tools), and the share's end logs what it
/// said about the capture and the converter. The app never asks for it.
#[cfg(test)]
mod debug_layer {
    use windows::core::Interface;
    use windows::Win32::Graphics::Direct3D11::{
        ID3D11Device, ID3D11InfoQueue, D3D11_CREATE_DEVICE_DEBUG, D3D11_CREATE_DEVICE_FLAG,
        D3D11_MESSAGE, D3D11_MESSAGE_SEVERITY_CORRUPTION, D3D11_MESSAGE_SEVERITY_ERROR,
        D3D11_MESSAGE_SEVERITY_WARNING,
    };

    fn wanted() -> bool {
        std::env::var("RIFT_D3D11_DEBUG").is_ok_and(|v| v == "1")
    }

    pub(super) fn flag() -> D3D11_CREATE_DEVICE_FLAG {
        if wanted() {
            D3D11_CREATE_DEVICE_DEBUG
        } else {
            D3D11_CREATE_DEVICE_FLAG(0)
        }
    }

    /// Reads the share's device while it is still held, before the encoder's
    /// last reference goes.
    pub(super) fn report() {
        if !wanted() {
            return;
        }
        let device: Option<ID3D11Device> = super::share_device();
        let Some(Ok(queue)) = device.map(|d| d.cast::<ID3D11InfoQueue>()) else {
            log::info!("capture: debug layer: no info queue");
            return;
        };
        let (mut corruption, mut errors, mut warnings, mut other) = (0, 0, 0, 0);
        // SAFETY: each message is read into a buffer of the length the queue
        // asked for, aligned for `D3D11_MESSAGE`, and read only while it lives.
        unsafe {
            let stored = queue.GetNumStoredMessages();
            for i in 0..stored {
                let mut len = 0;
                if queue.GetMessage(i, None, &mut len).is_err() || len == 0 {
                    continue;
                }
                let mut buf = vec![0u64; len.div_ceil(8)];
                let message = buf.as_mut_ptr().cast::<D3D11_MESSAGE>();
                if queue.GetMessage(i, Some(message), &mut len).is_err() {
                    continue;
                }
                let m = &*message;
                let shown = match m.Severity {
                    D3D11_MESSAGE_SEVERITY_CORRUPTION => {
                        corruption += 1;
                        corruption <= 10
                    }
                    D3D11_MESSAGE_SEVERITY_ERROR => {
                        errors += 1;
                        errors <= 10
                    }
                    D3D11_MESSAGE_SEVERITY_WARNING => {
                        warnings += 1;
                        warnings <= 10
                    }
                    _ => {
                        other += 1;
                        false
                    }
                };
                if shown {
                    let text = std::slice::from_raw_parts(
                        m.pDescription.cast::<u8>(),
                        m.DescriptionByteLength.saturating_sub(1),
                    );
                    log::info!(
                        "capture: debug layer {:?}: {}",
                        m.Severity,
                        String::from_utf8_lossy(text)
                    );
                }
            }
            log::info!(
                "capture: debug layer: {stored} messages | corruption {corruption} | errors \
                 {errors} | warnings {warnings} | other {other}"
            );
        }
    }
}

#[cfg(not(test))]
mod debug_layer {
    use windows::Win32::Graphics::Direct3D11::D3D11_CREATE_DEVICE_FLAG;

    pub(super) fn flag() -> D3D11_CREATE_DEVICE_FLAG {
        D3D11_CREATE_DEVICE_FLAG(0)
    }

    pub(super) fn report() {}
}

fn open_device(vendor: u32) -> windows::core::Result<(ID3D11Device, IDirect3DDevice)> {
    let adapter = adapter_of(vendor).ok_or(windows::core::Error::from_hresult(
        windows::Win32::Foundation::E_FAIL,
    ))?;
    let mut device = None;
    // SAFETY: `device` is written and read here only.
    unsafe {
        D3D11CreateDevice(
            &adapter,
            D3D_DRIVER_TYPE_UNKNOWN,
            HMODULE::default(),
            D3D11_CREATE_DEVICE_BGRA_SUPPORT | debug_layer::flag(),
            None::<&[D3D_FEATURE_LEVEL]>,
            D3D11_SDK_VERSION,
            Some(&mut device),
            None,
            None,
        )?;
    }
    let device: ID3D11Device = device.ok_or(windows::core::Error::from_hresult(
        windows::Win32::Foundation::E_FAIL,
    ))?;
    // The frame pool's thread and `gpu-encoder` both use it.
    let multithread: ID3D10Multithread = device.cast()?;
    // SAFETY: both calls on a live device.
    let winrt = unsafe {
        let _ = multithread.SetMultithreadProtected(true);
        let dxgi: IDXGIDevice = device.cast()?;
        CreateDirect3D11DeviceFromDXGIDevice(&dxgi)?
    };
    #[cfg(test)]
    counts::DEVICES.fetch_add(1, Ordering::Relaxed);
    Ok((device, winrt.cast()?))
}

/// WinRT on this thread, and the capture library kept loaded for good.
fn hold_winrt() {
    static LOADED: OnceLock<()> = OnceLock::new();
    LOADED.get_or_init(|| {
        // SAFETY: a system library, never freed; FFmpeg's comment on this one:
        // "letting it get auto-freed during RoUninit causes crashes".
        let _ = unsafe {
            LoadLibraryExW(
                &HSTRING::from("graphicscapture.dll"),
                None,
                LOAD_LIBRARY_SEARCH_SYSTEM32,
            )
        };
    });
    // SAFETY: joins the process's multithreaded apartment, or finds this thread
    // already in one; never left, which is what keeps WinRT up as a session closes.
    let _ = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
}

/// The monitor behind a screen's id in libwebrtc's list, which is its place among
/// the display devices (`GetHmonitorFromDeviceIndex` in libwebrtc).
fn monitor_of(id: u64) -> Option<HMONITOR> {
    let mut device = DISPLAY_DEVICEW {
        cb: std::mem::size_of::<DISPLAY_DEVICEW>() as u32,
        ..Default::default()
    };
    // SAFETY: `device` is the size it says.
    unsafe { EnumDisplayDevicesW(None, id as u32, &mut device, 0) }
        .as_bool()
        .then_some(())?;

    struct Search {
        name: [u16; 32],
        found: Option<HMONITOR>,
    }
    unsafe extern "system" fn look(
        monitor: HMONITOR,
        _: HDC,
        _: *mut RECT,
        search: LPARAM,
    ) -> BOOL {
        let search = &mut *(search.0 as *mut Search);
        let mut info = MONITORINFOEXW {
            monitorInfo: MONITORINFO {
                cbSize: std::mem::size_of::<MONITORINFOEXW>() as u32,
                ..Default::default()
            },
            ..Default::default()
        };
        if GetMonitorInfoW(monitor, &mut info.monitorInfo).as_bool() && info.szDevice == search.name
        {
            search.found = Some(monitor);
            return false.into();
        }
        true.into()
    }
    let mut search = Search {
        name: device.DeviceName,
        found: None,
    };
    // SAFETY: `search` outlives the call, which runs `look` only within it.
    let _ = unsafe {
        EnumDisplayMonitors(
            None,
            None,
            Some(look),
            LPARAM(&mut search as *mut Search as isize),
        )
    };
    search.found
}

/// The session a window share runs on, as [`SharedWindow`] takes it again when a
/// game swaps its window.
struct Running<'a> {
    capturer: &'a DesktopCapturer,
    device: &'a IDirect3DDevice,
    cursor: bool,
    flow: &'a Arc<Flow>,
    session: Option<Session>,
}

impl Recapture for Running<'_> {
    fn listed(&self) -> Vec<Source> {
        self.capturer.get_source_list()
    }

    fn capture(&mut self, source: Source) {
        self.session = None;
        match open_session(
            self.device,
            Target::Window(source.id()),
            self.cursor,
            self.flow,
        ) {
            Ok(session) => self.session = Some(session),
            Err(e) => log::warn!("capture: the window's new session did not open: {e}"),
        }
    }
}

/// Runs the share on Rift's own capture until a stop, the source's end, or a feed
/// that needs pictures in memory, which hands over to libwebrtc's capturer.
pub(super) fn run(
    request: CaptureRequest,
    fps: &Arc<AtomicU32>,
    progress: &UnboundedSender<Progress>,
    slot: &capture::VideoSlot,
    command_rx: &mpsc::Receiver<Command>,
) -> Handoff {
    // Asked only with the switch on: the answer opens an encoder to find out.
    let vendor = request.gpu_capture.then(encoder::takes_textures).flatten();
    let takes = takes_rifts_capture(
        request.gpu_capture,
        request.codec,
        vendor.is_some(),
        request.source_type,
        sources::screens_on_wgc(),
    );
    let Some(vendor) = vendor.filter(|_| takes) else {
        log::info!(
            "capture: GPU capture {}; libwebrtc's capturer",
            if request.gpu_capture {
                "does not fit this share"
            } else {
                "is off"
            }
        );
        return Handoff::Fallback(request);
    };
    let (device, winrt_device) = match open_device(vendor) {
        Ok(devices) => devices,
        Err(e) => {
            log::info!("capture: no D3D11 device for GPU capture ({e}); libwebrtc's capturer");
            return Handoff::Fallback(request);
        }
    };
    hold_winrt();
    let _timer = capture::TimerResolutionGuard::new();

    // The list is still libwebrtc's, so a share and its picker agree on ids.
    let Some(capturer) = DesktopCapturer::new(sources::options(request.source_type)) else {
        return Handoff::Fallback(request);
    };
    let source = match capture::find_source(&capturer, &request, progress, command_rx) {
        Ok(Some(source)) => source,
        Ok(None) => return Handoff::Done,
        Err(reason) => {
            let _ = progress.send(Progress::Failed(reason));
            return Handoff::Done;
        }
    };
    log::info!("capture: source {}", source.title());
    let is_window = request.source_type == DesktopCaptureSourceType::Window;
    let target = if is_window {
        Some(Target::Window(source.id()))
    } else {
        monitor_of(source.id()).map(Target::Screen)
    };
    let Some(target) = target else {
        log::info!("capture: no monitor for that screen; libwebrtc's capturer");
        return Handoff::Fallback(request);
    };

    *SHARE_DEVICE.lock().unwrap() = Some(SharedDevice(device));
    let _device_held = DeviceHeld;
    let (put, pictures) = latest::channel::<WgcPicture>();
    let flow = Arc::new(Flow {
        pictures: Mutex::new(Some(put)),
        first: Mutex::new(Some(progress.clone())),
        lost: AtomicBool::new(false),
        arrived: AtomicBool::new(false),
        fps: fps.clone(),
        pacer: Mutex::new(Pacer::new()),
    });
    let session = match open_session(&winrt_device, target, request.capture_cursor, &flow) {
        Ok(session) => session,
        Err(e) => {
            log::warn!("capture: Rift's capture did not open ({e}); libwebrtc's capturer");
            return Handoff::Fallback(request);
        }
    };
    log::info!("capture: on Rift's Windows Graphics Capture session");
    #[cfg(test)]
    counts::SESSIONS.fetch_add(1, Ordering::Relaxed);
    let wants_memory = Arc::new(AtomicBool::new(false));
    let processing = slot.clone();
    let told = wants_memory.clone();
    let _processing = thread::Builder::new()
        .name("share-frames".to_string())
        .spawn(move || process(pictures, processing, told))
        .expect("no processing thread");

    let mut running = Running {
        capturer: &capturer,
        device: &winrt_device,
        cursor: request.capture_cursor,
        flow: &flow,
        session: Some(session),
    };
    let mut window = is_window.then(|| SharedWindow::new(source.id(), source.title()));
    let mut rate = fps.load(Ordering::Relaxed);
    let hand_over = loop {
        match command_rx.recv_timeout(POLL) {
            Ok(Command::Terminate) | Err(RecvTimeoutError::Disconnected) => break false,
            Err(RecvTimeoutError::Timeout) => {}
        }
        if wants_memory.load(Ordering::Relaxed) {
            log::info!("capture: this feed reads memory; on to libwebrtc's capturer");
            break true;
        }
        let ended = match window.as_mut() {
            Some(window) => window.ended(
                &flow.lost,
                &flow.arrived,
                &mut running,
                request.on_paused.as_deref(),
            ),
            None => flow.lost.load(Ordering::Relaxed),
        };
        if ended {
            log::info!("capture: source closed, ending the share");
            #[cfg(test)]
            counts::CLOSED.fetch_add(1, Ordering::Relaxed);
            crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
            break false;
        }
        let now = fps.load(Ordering::Relaxed);
        if now != rate {
            log::info!("capture: now {now} fps");
            rate = now;
            if let Some(session) = &running.session {
                let _ = session.session.SetMinUpdateInterval(update_interval(now));
            }
        }
    };
    // The session first, then the mailbox, which ends the processing thread.
    drop(running);
    flow.pictures.lock().unwrap().take();
    drop(capturer);
    debug_layer::report();
    log::info!("capture: thread exiting");
    if hand_over {
        Handoff::Fallback(request)
    } else {
        Handoff::Done
    }
}

/// The processing thread: each picture to its feed. The newest is kept until a GPU
/// feed has taken it: the first comes before any feed, the rate gate can leave one
/// out, and on a still screen nothing newer comes to take its place.
fn process(pictures: Taker<WgcPicture>, slot: capture::VideoSlot, wants_memory: Arc<AtomicBool>) {
    let mut newest: Option<Arc<WgcPicture>> = None;
    let mut taken: Weak<GpuFeed> = Weak::new();
    loop {
        match pictures.take_timeout(QUIET) {
            Some(picture) => {
                // The older one goes back first, so the pool is short one the less.
                drop(newest.take());
                taken = Weak::new();
                newest = Some(Arc::new(picture));
            }
            None if pictures.closed() => break,
            None => {}
        }
        let Some(picture) = &newest else { continue };
        let Some((feed, target)) = slot.feed(picture.size()) else {
            continue;
        };
        match feed {
            Feed::Gpu(gpu) if gpu.takes_gpu_picture() => {
                if !Weak::ptr_eq(&taken, &Arc::downgrade(&gpu))
                    && gpu.send(Picture::Wgc(picture.clone()), target, now_us())
                {
                    taken = Arc::downgrade(&gpu);
                }
            }
            // VP9 after a fall back, or an encoder opened without the device.
            _ => {
                wants_memory.store(true, Ordering::Relaxed);
                return;
            }
        }
    }
}

/// Test builds only: what this module opened and heard, for the live tests.
#[cfg(test)]
pub(super) mod counts {
    use std::sync::atomic::AtomicU32;

    /// D3D11 devices opened for a share.
    pub(in super::super) static DEVICES: AtomicU32 = AtomicU32::new(0);
    /// Shares that ran on Rift's own session.
    pub(in super::super) static SESSIONS: AtomicU32 = AtomicU32::new(0);
    /// Shared windows heard closing.
    pub(in super::super) static CLOSED: AtomicU32 = AtomicU32::new(0);
}

/// Test builds only: how often Windows hands a picture over, how many go on,
/// and the gaps between arrivals, for the bench's log.
#[cfg(test)]
pub(super) mod arrivals {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Mutex;
    use std::time::Instant;

    /// Gap upper bounds in ms; the last bucket is everything longer.
    const EDGES: [f64; 8] = [3.0, 5.0, 7.0, 9.5, 13.0, 18.0, 23.0, 35.0];
    static ARRIVED: AtomicU64 = AtomicU64::new(0);
    static KEPT: AtomicU64 = AtomicU64::new(0);
    static GAPS: [AtomicU64; 9] = [const { AtomicU64::new(0) }; 9];
    static LAST: Mutex<Option<Instant>> = Mutex::new(None);

    pub(in super::super) fn arrived(now: Instant) {
        ARRIVED.fetch_add(1, Ordering::Relaxed);
        let mut last = LAST.lock().unwrap();
        if let Some(prev) = last.replace(now) {
            let ms = now.duration_since(prev).as_secs_f64() * 1000.0;
            let i = EDGES.iter().position(|&e| ms < e).unwrap_or(EDGES.len());
            GAPS[i].fetch_add(1, Ordering::Relaxed);
        }
    }

    pub(in super::super) fn kept() {
        KEPT.fetch_add(1, Ordering::Relaxed);
    }

    /// Since the last call: arrived, kept, and the gap counts by bucket.
    pub(in super::super) fn take() -> String {
        let gaps: Vec<String> = GAPS
            .iter()
            .enumerate()
            .map(|(i, g)| {
                let label = if i < EDGES.len() {
                    format!("<{}", EDGES[i])
                } else {
                    format!(">={}", EDGES[EDGES.len() - 1])
                };
                format!("{label}:{}", g.swap(0, Ordering::Relaxed))
            })
            .collect();
        format!(
            "arrived {} kept {} | gaps ms {}",
            ARRIVED.swap(0, Ordering::Relaxed),
            KEPT.swap(0, Ordering::Relaxed),
            gaps.join(" ")
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WINDOW: DesktopCaptureSourceType = DesktopCaptureSourceType::Window;
    const SCREEN: DesktopCaptureSourceType = DesktopCaptureSourceType::Screen;

    #[test]
    fn the_switch_keeps_a_share_out() {
        assert!(!takes_rifts_capture(
            false,
            VideoCodec::H264,
            true,
            SCREEN,
            true
        ));
        assert!(takes_rifts_capture(
            true,
            VideoCodec::H264,
            true,
            SCREEN,
            true
        ));
    }

    #[test]
    fn vp9_and_an_encoder_taking_memory_stay_on_libwebrtc() {
        assert!(!takes_rifts_capture(
            true,
            VideoCodec::VP9,
            true,
            SCREEN,
            true
        ));
        assert!(!takes_rifts_capture(
            true,
            VideoCodec::H264,
            false,
            SCREEN,
            true
        ));
    }

    #[test]
    fn windows_10_keeps_dxgi_for_a_screen_but_not_a_window() {
        assert!(!takes_rifts_capture(
            true,
            VideoCodec::H264,
            true,
            SCREEN,
            false
        ));
        assert!(takes_rifts_capture(
            true,
            VideoCodec::H264,
            true,
            WINDOW,
            false
        ));
    }

    /// Counts what a screen refreshing at `hz` gets through a pacer at `fps`.
    fn admitted(hz: f64, fps: u32) -> u32 {
        let start = Instant::now();
        let mut pacer = Pacer::new();
        (0..(hz as u32 * 10))
            .filter(|tick| {
                pacer.admits(start + Duration::from_secs_f64(f64::from(*tick) / hz), fps)
            })
            .count() as u32
    }

    #[test]
    fn a_faster_screen_is_paced_to_the_share() {
        // Ten seconds of each: within a picture or two of the share's rate, even
        // where the screen's does not divide into it.
        assert!(admitted(165.0, 60).abs_diff(600) <= 2);
        assert!(admitted(240.0, 60).abs_diff(600) <= 2);
        assert!(admitted(165.0, 120).abs_diff(1200) <= 2);
    }

    #[test]
    fn a_source_just_above_the_rate_does_not_beat_against_it() {
        assert!(admitted(62.0, 60).abs_diff(600) <= 2);
    }

    #[test]
    fn a_slower_screen_is_all_let_through() {
        assert_eq!(admitted(60.0, 120), 600);
    }

    #[test]
    fn a_pause_is_not_made_up_in_a_burst() {
        let start = Instant::now();
        let mut pacer = Pacer::new();
        assert!(pacer.admits(start, 60));
        let later = start + Duration::from_secs(5);
        assert!(pacer.admits(later, 60));
        assert!(!pacer.admits(later + Duration::from_millis(2), 60));
    }
}
