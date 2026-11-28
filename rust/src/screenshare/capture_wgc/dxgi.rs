//! A whole screen on Windows 10, captured with DXGI desktop duplication on the
//! share's own device, so each picture stays on the GPU like a Windows Graphics
//! Capture one.
//!
//! Windows Graphics Capture draws a yellow border round a captured screen on
//! Windows 10 that cannot be turned off, so a screen there was left to
//! libwebrtc's DXGI capturer (`sources::options`). That one copies every
//! picture to memory, converts it on the CPU and uploads it again, on the
//! share's capture thread, sixty times a second: beside RDR2 a friend's
//! whole-screen share fell to 1–18 fps, while his window share of another game,
//! on Rift's own capture, held 60 (Nov 18 2026 review, A3). Duplicating the
//! output here gives the same picture with no border and no trip through memory.
//!
//! As Sunshine's `display_vram.cpp` and OBS's `duplicator-monitor-capture` do,
//! each new desktop image is copied out of the duplication's texture at once,
//! and the duplication's frame let go: the next picture can then come while the
//! encoder reads this one. DXGI leaves the cursor out of its pictures, so it is
//! drawn into the copy here, on the GPU (`cursor`), the inverting ones too. Its
//! shape is the one the duplication hands over (`GetFramePointerShape`), as
//! Windows draws it: GDI's (`GetIconInfo`) is an animated cursor's first frame
//! at the base size, so a busy cursor stood still, a cursor enlarged in
//! Windows' pointer settings came out at 32 pixels, and a new pointer scheme
//! mid-share, which keeps the cursor's handle, went unseen (Nov 20 2026).
//!
//! On an HDR screen the duplication is asked for in 16 bits and each new
//! desktop image brought down to eight before anything else sees it (`hdr`).
//! Asked for eight bits there, Windows' copy leaves out the SDR brightness set
//! in its display settings, and the share came out dark (Nov 22 2026).
//!
//! An output can be duplicated once per process. libwebrtc's DXGI capturer
//! holds every output while it lives, so the share lets go of the one it found
//! its source with before this opens (`capture_wgc::run`).

use super::cursor::CursorDrawer;
use super::hdr::{self, Light, ToSdr, HDR_FORMAT};
use super::{Flow, WgcPicture};
use crate::screenshare::cursor_shape::dxgi_shape_images;
use crate::screenshare::pacer;
use crate::screenshare::resolution::Size;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use windows::core::{Error, Interface, Result, HRESULT};
use windows::Win32::Foundation::{E_ACCESSDENIED, E_FAIL, E_INVALIDARG, E_NOTIMPL, POINT, RECT};
use windows::Win32::Graphics::Direct3D10::ID3D10Multithread;
use windows::Win32::Graphics::Direct3D11::{
    ID3D11Device, ID3D11DeviceContext, ID3D11RenderTargetView, ID3D11Texture2D,
    D3D11_BIND_RENDER_TARGET, D3D11_BIND_SHADER_RESOURCE, D3D11_TEXTURE2D_DESC,
    D3D11_USAGE_DEFAULT,
};
use windows::Win32::Graphics::Dxgi::Common::{
    DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_MODE_ROTATION_IDENTITY, DXGI_MODE_ROTATION_UNSPECIFIED,
    DXGI_SAMPLE_DESC,
};
use windows::Win32::Graphics::Dxgi::{
    IDXGIDevice, IDXGIOutput1, IDXGIOutput5, IDXGIOutputDuplication, IDXGIResource,
    DXGI_ERROR_ACCESS_DENIED, DXGI_ERROR_ACCESS_LOST, DXGI_ERROR_NOT_CURRENTLY_AVAILABLE,
    DXGI_ERROR_NOT_FOUND, DXGI_ERROR_SESSION_DISCONNECTED, DXGI_ERROR_UNSUPPORTED,
    DXGI_ERROR_WAIT_TIMEOUT, DXGI_OUTDUPL_FRAME_INFO, DXGI_OUTDUPL_POINTER_SHAPE_INFO,
};
use windows::Win32::Graphics::Gdi::HMONITOR;
use windows::Win32::UI::WindowsAndMessaging::{GetCursorInfo, CURSORINFO, CURSOR_SHOWING};

/// The copies a picture is handed out in. One can wait in the capture's
/// mailbox, one in the processing thread (held by the pacer, or left out by the
/// rate gate), one in the encoder's mailbox and one be drawn by it, and one is
/// needed to copy the next into.
const COPIES: usize = 5;

/// The longest the duplication thread waits for a new desktop image before it
/// looks for a stop, or a cursor that moved without one.
const WAIT_MS: u32 = 20;

/// How long a duplication Windows took back waits before it is made again: a
/// mode change, a full-screen game taking the screen, or the secure desktop
/// of a UAC prompt or the lock screen, which cannot be duplicated while it is up.
const AGAIN_AFTER: Duration = Duration::from_millis(100);

/// How often an HDR screen's brightness is read again, for the SDR slider
/// moved in Windows' settings. Turning HDR on or off takes the duplication
/// back, and it is read again then too.
const LIGHT_EVERY: Duration = Duration::from_secs(2);

/// How often a slow cursor draw is reported.
const REPORT_EVERY: Duration = Duration::from_secs(5);

/// A cursor draw at least this long is reported. It only asks the GPU, so it
/// should take well under this unless the encoder holds the device.
const SLOW_DRAW: Duration = Duration::from_millis(2);

/// One of the copies a picture is handed out in, free again once its picture
/// has gone, and the view the cursor is drawn into it through.
pub(super) struct Copy(ID3D11Texture2D, ID3D11RenderTargetView);

// SAFETY: a texture on a multithread-protected device; this module writes it
// only while no picture holds it, and `gpu-encoder` only reads it.
unsafe impl Send for Copy {}
unsafe impl Sync for Copy {}

impl Copy {
    pub(super) fn texture(&self) -> &ID3D11Texture2D {
        &self.0
    }

    pub(super) fn view(&self) -> &ID3D11RenderTargetView {
        &self.1
    }
}

/// A copy no picture holds. Only one thread hands a set of copies out, so one
/// found free stays free.
pub(super) fn free(copies: &[Arc<Copy>]) -> Option<Arc<Copy>> {
    copies
        .iter()
        .find(|copy| Arc::strong_count(copy) == 1)
        .cloned()
}

/// A running duplication of one screen, stopped on drop.
pub(super) struct Duplication {
    stop: Arc<AtomicBool>,
    cursor: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl Duplication {
    /// Duplicate `monitor`'s output on `device`, which has to be on the GPU
    /// that drives it: DXGI refuses another, and a laptop whose screen hangs
    /// off its integrated GPU then shares through libwebrtc's capturer as before.
    pub(super) fn open(
        device: &ID3D11Device,
        monitor: HMONITOR,
        cursor: bool,
        flow: &Arc<Flow>,
    ) -> Result<Duplication> {
        let screen = Screen::open(device, monitor)?;
        let stop = Arc::new(AtomicBool::new(false));
        let shown = Arc::new(AtomicBool::new(cursor));
        let thread = thread::Builder::new()
            .name("share-duplicate".to_string())
            .spawn({
                let stop = stop.clone();
                let shown = shown.clone();
                let flow = flow.clone();
                move || {
                    crate::screenshare::priority::raise_this_thread();
                    duplicate(screen, &flow, &stop, &shown);
                }
            })
            .map_err(|_| Error::from_hresult(E_FAIL))?;
        #[cfg(test)]
        super::counts::DUPLICATIONS.fetch_add(1, Ordering::Relaxed);
        Ok(Duplication {
            stop,
            cursor: shown,
            thread: Some(thread),
        })
    }

    /// Draw the cursor into the pictures from now, or leave it out.
    pub(super) fn show_cursor(&self, shown: bool) {
        self.cursor.store(shown, Ordering::Relaxed);
    }
}

impl Drop for Duplication {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// The duplication and what its pictures are copied into.
struct Screen {
    device: ID3D11Device,
    context: ID3D11DeviceContext,
    /// Held across a cursor draw, whose states and draws must not mix with
    /// the encoder's commands on the device.
    lock: ID3D10Multithread,
    /// `None` if its shaders could not be made, and then no cursor is drawn.
    cursor: Option<CursorDrawer>,
    /// How many shapes the duplication has handed over: each one, an animated
    /// cursor's every frame too, makes a new picture.
    shapes: u64,
    /// What a shape is read into, kept between them.
    shape_bytes: Vec<u8>,
    /// Whether a shape that could not be read was logged.
    shape_failed: bool,
    monitor: HMONITOR,
    /// `None` while Windows has it back and it is being made again.
    duplication: Option<IDXGIOutputDuplication>,
    /// Where the output sits on the desktop, which the cursor's place is read on.
    desktop: RECT,
    size: Size,
    /// The newest desktop image, without the cursor: a cursor that moves on a
    /// still screen is drawn again over it.
    image: ID3D11Texture2D,
    copies: Vec<Arc<Copy>>,
    /// `Some` while the screen is in HDR.
    light: Option<Light>,
    light_read: Instant,
    /// An HDR screen's: its 16-bit image copied out of the duplication, which
    /// a shader cannot read, and what draws it into `image`. Made at the first
    /// such image.
    hdr: Option<HdrImage>,
}

struct HdrImage {
    to_sdr: ToSdr,
    image: ID3D11Texture2D,
    into: ID3D11RenderTargetView,
}

// SAFETY: made on the capture thread and used on the duplication thread alone
// from then; the device is multithread-protected.
unsafe impl Send for Screen {}

impl Screen {
    fn open(device: &ID3D11Device, monitor: HMONITOR) -> Result<Screen> {
        let light = hdr::light_of(monitor);
        hdr::log_light(light);
        let (duplication, desktop, size) = duplicate_output(device, monitor, light.is_some())?;
        // SAFETY: a live device.
        let context = unsafe { device.GetImmediateContext()? };
        let (image, copies) = textures(device, size)?;
        let cursor = CursorDrawer::new(device)
            .inspect_err(|e| log::warn!("capture: the cursor cannot be drawn: {e}"))
            .ok();
        Ok(Screen {
            device: device.clone(),
            context,
            lock: device.cast()?,
            cursor,
            shapes: 0,
            shape_bytes: Vec::new(),
            shape_failed: false,
            monitor,
            duplication: Some(duplication),
            desktop,
            size,
            image,
            copies,
            light,
            light_read: Instant::now(),
            hdr: None,
        })
    }

    /// Duplicate the output again, after Windows took the last one back, which
    /// goes first: an output is duplicated once per process. New textures if
    /// the screen changed size; pictures still out in the old copies keep them
    /// until they go.
    fn again(&mut self) -> Result<()> {
        self.duplication = None;
        let light = hdr::light_of(self.monitor);
        if light.is_some() != self.light.is_some() {
            hdr::log_light(light);
        }
        self.light = light;
        self.light_read = Instant::now();
        let (duplication, desktop, size) =
            duplicate_output(&self.device, self.monitor, light.is_some())?;
        if size != self.size {
            log::info!("capture: the screen is now {}x{}", size.width, size.height);
            (self.image, self.copies) = textures(&self.device, size)?;
            self.hdr = None;
        }
        self.duplication = Some(duplication);
        self.desktop = desktop;
        self.size = size;
        Ok(())
    }

    /// A copy no picture holds.
    fn free_copy(&self) -> Option<Arc<Copy>> {
        free(&self.copies)
    }

    /// The screen's brightness read again, now and then.
    fn read_light(&mut self) {
        if self.light.is_none() || self.light_read.elapsed() < LIGHT_EVERY {
            return;
        }
        self.light_read = Instant::now();
        // Gone to SDR: the duplication is taken back, and read again then.
        if let Some(light) = hdr::light_of(self.monitor) {
            if Some(light) != self.light {
                hdr::log_light(Some(light));
            }
            self.light = Some(light);
        }
    }

    /// Take `desktop`, a 16-bit image of the screen's size, into `image` in
    /// eight bits. False when it cannot be.
    fn bring_down(&mut self, desktop: &ID3D11Texture2D) -> bool {
        if self.hdr.is_none() {
            let made = ToSdr::new(&self.device).and_then(|to_sdr| {
                let image = hdr_texture(&self.device, self.size)?;
                let mut into = None;
                // SAFETY: a texture made to be drawn into, on this device.
                unsafe {
                    self.device
                        .CreateRenderTargetView(&self.image, None, Some(&mut into))?
                };
                let into = into.ok_or_else(|| Error::from_hresult(E_FAIL))?;
                Ok(HdrImage {
                    to_sdr,
                    image,
                    into,
                })
            });
            match made {
                Ok(made) => self.hdr = Some(made),
                Err(e) => {
                    log::warn!("capture: HDR pictures cannot be drawn: {e}");
                    return false;
                }
            }
        }
        let Some(hdr) = &self.hdr else {
            return false;
        };
        // SAFETY: the same size and format, on the same device.
        unsafe { self.context.CopyResource(&hdr.image, desktop) };
        let light = self.light.unwrap_or_else(Light::unread);
        match hdr.to_sdr.draw(&hdr.image, &hdr.into, self.size, light) {
            Ok(()) => true,
            Err(e) => {
                log::warn!("capture: an HDR picture was not drawn: {e}");
                false
            }
        }
    }

    /// Take the cursor's new shape from the frame `duplication` holds, `size`
    /// bytes of it. One that cannot be read leaves the cursor out until the next.
    fn read_shape(&mut self, duplication: &IDXGIOutputDuplication, size: u32) {
        let Some(drawer) = self.cursor.as_mut() else {
            return;
        };
        self.shapes += 1;
        self.shape_bytes.resize(size as usize, 0);
        let mut info = DXGI_OUTDUPL_POINTER_SHAPE_INFO::default();
        let mut needed = 0;
        // SAFETY: the buffer holds `size` bytes; the frame is still held.
        let read = unsafe {
            duplication.GetFramePointerShape(
                size,
                self.shape_bytes.as_mut_ptr().cast(),
                &mut needed,
                &mut info,
            )
        };
        let shape = read.and_then(|()| {
            let bytes = &self.shape_bytes[..needed.min(size) as usize];
            let images = dxgi_shape_images(
                info.Type,
                info.Width,
                info.Height,
                info.Pitch as usize,
                bytes,
            )
            .ok_or_else(|| {
                Error::new(
                    E_FAIL,
                    format!(
                        "a shape of kind {} at {}x{} cannot be drawn",
                        info.Type, info.Width, info.Height
                    ),
                )
            })?;
            drawer.set_shape(&self.device, &images, info.HotSpot)
        });
        if let Err(e) = shape {
            drawer.forget();
            if !self.shape_failed {
                self.shape_failed = true;
                log::info!("capture: the cursor's shape could not be read: {e}");
            }
        }
    }

    /// Draw the cursor into `copy` on the GPU, in the shape last handed over.
    fn draw_cursor(&self, copy: &Copy, pointer: Pointer) {
        let Some(drawer) = self.cursor.as_ref() else {
            return;
        };
        let Some(hot_spot) = drawer.hot_spot() else {
            return;
        };
        let corner = cursor_corner(pointer.at, &self.desktop, hot_spot);
        // SAFETY: the device is held across the draw's states and draws, and
        // no picture holds the copy yet.
        unsafe {
            self.lock.Enter();
            drawer.draw(&self.context, &copy.1, corner);
            self.lock.Leave();
        }
        #[cfg(test)]
        super::counts::CURSORS_DRAWN.fetch_add(1, Ordering::Relaxed);
    }
}

/// The newest image's texture and the copies, at `size`.
fn textures(device: &ID3D11Device, size: Size) -> Result<(ID3D11Texture2D, Vec<Arc<Copy>>)> {
    // Drawn into from an HDR screen's image.
    let image = texture(device, size, true)?;
    Ok((image, copies(device, size)?))
}

/// The copies pictures are handed out in, at `size`.
pub(super) fn copies(device: &ID3D11Device, size: Size) -> Result<Vec<Arc<Copy>>> {
    (0..COPIES)
        .map(|_| {
            let texture = texture(device, size, true)?;
            let mut view = None;
            // SAFETY: a texture made to be drawn into, on this device.
            unsafe { device.CreateRenderTargetView(&texture, None, Some(&mut view))? };
            let view = view.ok_or_else(|| Error::from_hresult(E_FAIL))?;
            Ok(Arc::new(Copy(texture, view)))
        })
        .collect::<Result<Vec<_>>>()
}

/// The duplication of `monitor`'s output on `device`, where that output sits,
/// and its size. An `hdr` screen's comes in 16 bits where Windows can give it.
fn duplicate_output(
    device: &ID3D11Device,
    monitor: HMONITOR,
    hdr: bool,
) -> Result<(IDXGIOutputDuplication, RECT, Size)> {
    let dxgi: IDXGIDevice = device.cast()?;
    // SAFETY: DXGI calls on live objects, their results checked.
    unsafe {
        let adapter = dxgi.GetAdapter()?;
        let output = (0..)
            .map_while(|at| adapter.EnumOutputs(at).ok())
            .find(|output| output.GetDesc().is_ok_and(|desc| desc.Monitor == monitor))
            .ok_or_else(|| {
                Error::new(
                    DXGI_ERROR_NOT_FOUND,
                    "the screen is not on the encoder's GPU",
                )
            })?;
        let placed = output.GetDesc()?.DesktopCoordinates;
        // DuplicateOutput1 is from Windows 10 1703 and wants a process aware
        // of each monitor's DPI, which the runner's manifest makes Rift.
        let in_16_bits = hdr
            .then(|| output.cast::<IDXGIOutput5>().ok())
            .flatten()
            .and_then(|output| {
                output
                    .DuplicateOutput1(device, 0, &[HDR_FORMAT, DXGI_FORMAT_B8G8R8A8_UNORM])
                    .inspect_err(|e| log::info!("capture: no 16-bit duplication: {e}"))
                    .ok()
            });
        let duplication = match in_16_bits {
            Some(duplication) => duplication,
            None => output.cast::<IDXGIOutput1>()?.DuplicateOutput(device)?,
        };
        let desc = duplication.GetDesc();
        // A turned screen comes unturned, and the system-memory kind is only a
        // basic display driver's: libwebrtc's capturer copes with both. Told
        // with a code of Rift's own, so neither is taken for a passing refusal.
        if desc.Rotation != DXGI_MODE_ROTATION_IDENTITY
            && desc.Rotation != DXGI_MODE_ROTATION_UNSPECIFIED
        {
            return Err(Error::new(E_NOTIMPL, "the screen is turned"));
        }
        if desc.DesktopImageInSystemMemory.as_bool() {
            return Err(Error::new(E_NOTIMPL, "the desktop image is in memory"));
        }
        let size = Size {
            width: desc.ModeDesc.Width,
            height: desc.ModeDesc.Height,
        };
        Ok((duplication, placed, size))
    }
}

/// A BGRA texture of `size`, that can be drawn into and read by a shader: the
/// cursor and an HDR image are drawn into it, and the encoder's conversion
/// reads it.
fn texture(device: &ID3D11Device, size: Size, drawn: bool) -> Result<ID3D11Texture2D> {
    made_texture(device, size, DXGI_FORMAT_B8G8R8A8_UNORM, drawn)
}

/// A 16-bit texture of `size` an HDR image is copied into, for a shader to read.
fn hdr_texture(device: &ID3D11Device, size: Size) -> Result<ID3D11Texture2D> {
    made_texture(device, size, HDR_FORMAT, false)
}

fn made_texture(
    device: &ID3D11Device,
    size: Size,
    format: windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT,
    drawn: bool,
) -> Result<ID3D11Texture2D> {
    let desc = D3D11_TEXTURE2D_DESC {
        Width: size.width,
        Height: size.height,
        MipLevels: 1,
        ArraySize: 1,
        Format: format,
        SampleDesc: DXGI_SAMPLE_DESC {
            Count: 1,
            Quality: 0,
        },
        Usage: D3D11_USAGE_DEFAULT,
        BindFlags: if drawn {
            (D3D11_BIND_SHADER_RESOURCE.0 | D3D11_BIND_RENDER_TARGET.0) as u32
        } else {
            D3D11_BIND_SHADER_RESOURCE.0 as u32
        },
        CPUAccessFlags: 0,
        MiscFlags: 0,
    };
    let mut made = None;
    // SAFETY: `made` is written and read here only.
    unsafe { device.CreateTexture2D(&desc, None, Some(&mut made))? };
    made.ok_or_else(|| Error::from_hresult(E_FAIL))
}

/// The cursor as it would be drawn: where, in which of the shapes handed over,
/// and whether at all. A hidden one is always the same, so it moving makes no
/// picture.
#[derive(Clone, Copy, PartialEq, Debug, Default)]
struct Pointer {
    shown: bool,
    at: (i32, i32),
    shape: u64,
}

impl Pointer {
    /// The cursor now, as it shows on the screen at `desktop`, in shape `shape`.
    fn now(desktop: &RECT, shape: u64) -> Pointer {
        let mut info = CURSORINFO {
            cbSize: std::mem::size_of::<CURSORINFO>() as u32,
            ..Default::default()
        };
        // SAFETY: `info` is the size it says.
        if unsafe { GetCursorInfo(&mut info) }.is_err() {
            return Pointer::default();
        }
        // A game that hides the cursor clears the flag.
        let showing = info.flags.0 & CURSOR_SHOWING.0 != 0 && !info.hCursor.is_invalid();
        let at = (info.ptScreenPos.x, info.ptScreenPos.y);
        if !showing || !on_screen(at, desktop) {
            return Pointer::default();
        }
        Pointer {
            shown: true,
            at,
            shape,
        }
    }
}

/// Whether a point on the desktop is on the screen at `desktop`.
fn on_screen(at: (i32, i32), desktop: &RECT) -> bool {
    (desktop.left..desktop.right).contains(&at.0) && (desktop.top..desktop.bottom).contains(&at.1)
}

/// Where a cursor's image goes in a screen's picture: its place on the desktop,
/// less the screen's corner and the cursor's hot spot.
fn cursor_corner(at: (i32, i32), desktop: &RECT, hot_spot: POINT) -> (i32, i32) {
    (
        at.0 - desktop.left - hot_spot.x,
        at.1 - desktop.top - hot_spot.y,
    )
}

/// Whether DXGI refused for a reason that passes: the duplication taken back
/// at a mode change or a full-screen game, the secure desktop of a UAC prompt
/// or the lock screen, a session switching, or another duplication of the
/// output (libwebrtc's, for the share dialog's list) not yet let go.
fn passing(code: HRESULT) -> bool {
    [
        DXGI_ERROR_ACCESS_LOST,
        DXGI_ERROR_ACCESS_DENIED,
        E_ACCESSDENIED,
        DXGI_ERROR_UNSUPPORTED,
        DXGI_ERROR_SESSION_DISCONNECTED,
        DXGI_ERROR_NOT_CURRENTLY_AVAILABLE,
        E_INVALIDARG,
    ]
    .contains(&code)
}

/// The duplication thread: each new desktop image or cursor move, at no more
/// than the rate Windows Graphics Capture is asked for (`pacer::asked_rate`),
/// into a free copy and on to `flow`, as the frame pool's event puts its own.
///
/// It stamps `flow.last` while it runs, waiting or not: a duplication that
/// answers is alive, unlike a quiet Windows Graphics Capture session, and is
/// made again here when Windows takes it back. The share's quiet watch then
/// steps in only once this thread has stopped, on an error that does not pass.
fn duplicate(mut screen: Screen, flow: &Flow, stop: &AtomicBool, cursor: &AtomicBool) {
    let stamp = || *flow.last.lock().unwrap() = Instant::now();
    let mut have_image = false;
    // A new desktop image not yet handed out, kept when every copy is out.
    let mut pending = false;
    let mut drawn: Option<Pointer> = None;
    let mut next = Instant::now();
    let mut slowest = Duration::ZERO;
    let mut reported = Instant::now();
    let mut lost_at: Option<Instant> = None;
    while !stop.load(Ordering::Relaxed) {
        if let Some(at) = lost_at {
            stamp();
            thread::sleep(AGAIN_AFTER);
            match screen.again() {
                Ok(()) => {
                    log::info!(
                        "capture: duplicating the screen again after {} ms",
                        at.elapsed().as_millis()
                    );
                    lost_at = None;
                    have_image = false;
                }
                Err(e) if passing(e.code()) => {}
                Err(e) => {
                    // The output went, or turned: the quiet watch opens a new
                    // duplication, and hands the share over if none opens.
                    log::warn!("capture: the screen cannot be duplicated again: {e}");
                    return;
                }
            }
            continue;
        }
        let Some(duplication) = screen.duplication.clone() else {
            lost_at = Some(Instant::now());
            continue;
        };
        let now = Instant::now();
        if now < next {
            thread::sleep((next - now).min(Duration::from_millis(u64::from(WAIT_MS))));
            continue;
        }

        let mut info = DXGI_OUTDUPL_FRAME_INFO::default();
        let mut resource: Option<IDXGIResource> = None;
        // SAFETY: both are written by the call and read after it.
        let acquired = unsafe { duplication.AcquireNextFrame(WAIT_MS, &mut info, &mut resource) };
        stamp();
        match acquired {
            Ok(()) => {
                if info.LastPresentTime != 0 || !have_image {
                    if let Some(desktop) = resource
                        .as_ref()
                        .and_then(|r| r.cast::<ID3D11Texture2D>().ok())
                    {
                        let mut desc = D3D11_TEXTURE2D_DESC::default();
                        // SAFETY: `desc` is written, and nothing else is touched.
                        unsafe { desktop.GetDesc(&mut desc) };
                        let known =
                            desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM || desc.Format == HDR_FORMAT;
                        if !known
                            || desc.Width != screen.size.width
                            || desc.Height != screen.size.height
                        {
                            // A copy into eight bits a colour would do nothing,
                            // and the share be black.
                            log::warn!(
                                "capture: the screen comes as format {} at {}x{}; \
                                 not duplicated here",
                                desc.Format.0,
                                desc.Width,
                                desc.Height
                            );
                            // SAFETY: the frame acquired above.
                            let _ = unsafe { duplication.ReleaseFrame() };
                            return;
                        }
                        if desc.Format == HDR_FORMAT {
                            screen.read_light();
                            if !screen.bring_down(&desktop) {
                                // SAFETY: the frame acquired above.
                                let _ = unsafe { duplication.ReleaseFrame() };
                                return;
                            }
                        } else {
                            // SAFETY: the same size and format, on the same device.
                            unsafe { screen.context.CopyResource(&screen.image, &desktop) };
                        }
                        have_image = true;
                        pending = true;
                    }
                }
                if info.PointerShapeBufferSize > 0 {
                    screen.read_shape(&duplication, info.PointerShapeBufferSize);
                }
                drop(resource);
                // SAFETY: the frame acquired above, its image and shape already
                // copied out.
                if let Err(e) = unsafe { duplication.ReleaseFrame() } {
                    if passing(e.code()) {
                        lost_at = Some(Instant::now());
                        continue;
                    }
                }
            }
            Err(e) if e.code() == DXGI_ERROR_WAIT_TIMEOUT => {}
            Err(e) if passing(e.code()) => {
                lost_at = Some(Instant::now());
                continue;
            }
            Err(e) => {
                // A removed device, for one: the capture thread sees that
                // itself and hands the share over.
                log::warn!("capture: the screen's duplication failed: {e}");
                return;
            }
        }
        if !have_image {
            continue;
        }
        let pointer = if cursor.load(Ordering::Relaxed) {
            Pointer::now(&screen.desktop, screen.shapes)
        } else {
            Pointer::default()
        };
        if !pending && drawn == Some(pointer) {
            continue;
        }
        // Every copy is still out: this change goes in the next picture.
        let Some(copy) = screen.free_copy() else {
            continue;
        };
        // SAFETY: the same size and format, on the same device; no picture
        // holds the copy.
        unsafe { screen.context.CopyResource(copy.texture(), &screen.image) };
        if pointer.shown {
            let began = Instant::now();
            screen.draw_cursor(&copy, pointer);
            slowest = slowest.max(began.elapsed());
        }
        if reported.elapsed() >= REPORT_EVERY {
            if slowest >= SLOW_DRAW {
                log::info!(
                    "capture: drawing the cursor took up to {:.1} ms",
                    slowest.as_secs_f64() * 1000.0
                );
            }
            slowest = Duration::ZERO;
            reported = Instant::now();
        }
        drawn = Some(pointer);
        pending = false;
        flow.deliver(WgcPicture::copied(copy, screen.size));
        let rate = pacer::asked_rate(flow.fps.load(Ordering::Relaxed)).max(1);
        next = Instant::now() + Duration::from_secs(1) / rate;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A second screen to the right of a 1920-wide first one.
    const SECOND: RECT = RECT {
        left: 1920,
        top: 0,
        right: 3840,
        bottom: 1080,
    };

    #[test]
    fn the_cursor_is_placed_on_its_screen_by_its_hot_spot() {
        let corner = cursor_corner((2000, 500), &SECOND, POINT { x: 8, y: 8 });
        assert_eq!(corner, (72, 492));
    }

    #[test]
    fn a_cursor_on_another_screen_is_not_on_this_one() {
        assert!(on_screen((1920, 0), &SECOND));
        assert!(!on_screen((1919, 500), &SECOND));
        assert!(!on_screen((3840, 500), &SECOND));
    }
}
