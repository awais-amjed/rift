//! A chat video played by Windows' Media Engine ([`super::media_engine`]),
//! on a thread of its own that takes the app's requests and draws each
//! picture as it falls due.
//!
//! Where the runner's device can decode video, the engine is lent it, and a
//! picture never leaves the GPU: the engine draws it as NV12 into a texture
//! of the clip's, copied into a slice of an array the runner draws where it
//! lies, as it draws a watched share's (`IN_D3D11`). Elsewhere (no video
//! support on the runner's device) the engine has a device of its own and
//! each picture is read back into memory as I420, which every runner draws.
use super::emit;
use super::media_engine::{
    failure, own_device, protect, Com, Engine, Note, EVENT_ENDED, EVENT_ERROR,
};
use crate::api::clips::ClipEventKind;
use crate::watching::frames::{self, Picture, WatchPlanes, IN_D3D11};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;
use windows::core::Interface;
use windows::Win32::Foundation::RECT;
use windows::Win32::Graphics::Direct3D11::{
    ID3D11Device, ID3D11DeviceContext, ID3D11Texture2D, ID3D11VideoDevice,
    D3D11_BIND_RENDER_TARGET, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ,
    D3D11_MAPPED_SUBRESOURCE, D3D11_MAP_READ, D3D11_TEXTURE2D_DESC, D3D11_USAGE_DEFAULT,
    D3D11_USAGE_STAGING,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_NV12, DXGI_SAMPLE_DESC};

/// How often a playing clip asks for a new picture: often enough for 120
/// frames a second. Paused, it only waits for a seek's picture.
const PLAYING_TICK: Duration = Duration::from_millis(4);
const PAUSED_TICK: Duration = Duration::from_millis(25);

/// Slices in the array a GPU clip's pictures go into: one the runner draws,
/// one waiting for it, and one being written, with one to spare.
const SLICES: usize = 4;

/// [`AtomicU64`]'s "not known".
const UNKNOWN: u64 = u64::MAX;

enum Command {
    Play,
    Pause,
    Seek(u64),
    Volume(f64),
}

pub(crate) struct Clip {
    /// Taken when it is dropped, which ends its thread.
    commands: Option<Sender<Command>>,
    time: Arc<Time>,
    thread: Option<JoinHandle<()>>,
}

/// Where the clip is, written by its thread at every tick.
struct Time {
    position_ms: AtomicU64,
    duration_ms: AtomicU64,
}

impl Clip {
    pub(super) fn open(
        bytes: Vec<u8>,
        texture: u64,
        output: Option<String>,
    ) -> Result<Clip, String> {
        let (commands, inbox) = mpsc::channel();
        let time = Arc::new(Time {
            position_ms: AtomicU64::new(UNKNOWN),
            duration_ms: AtomicU64::new(UNKNOWN),
        });
        let (opened, open_result) = mpsc::sync_channel(1);
        let thread = {
            let time = time.clone();
            thread::Builder::new()
                .name("rift-clip".into())
                .spawn(move || run(bytes, texture, output, inbox, time, opened))
                .map_err(|e| format!("No thread for the video: {e}"))?
        };
        match open_result.recv() {
            Ok(Ok(())) => Ok(Clip {
                commands: Some(commands),
                time,
                thread: Some(thread),
            }),
            Ok(Err(e)) => {
                let _ = thread.join();
                Err(e)
            }
            Err(_) => {
                let _ = thread.join();
                Err("The video's thread stopped".to_string())
            }
        }
    }

    fn send(&self, command: Command) -> Result<(), String> {
        self.commands
            .as_ref()
            .and_then(|c| c.send(command).ok())
            .ok_or_else(|| "The video has stopped".to_string())
    }

    pub(crate) fn play(&self) -> Result<(), String> {
        self.send(Command::Play)
    }

    pub(crate) fn pause(&self) -> Result<(), String> {
        self.send(Command::Pause)
    }

    pub(crate) fn seek(&self, position_ms: u64) -> Result<(), String> {
        // Said at once, so a time read before the engine lands is not the
        // old place.
        self.time.position_ms.store(position_ms, Ordering::SeqCst);
        self.send(Command::Seek(position_ms))
    }

    pub(crate) fn set_volume(&self, volume: f64) {
        let _ = self.send(Command::Volume(volume));
    }

    pub(crate) fn time(&self) -> (Option<u64>, Option<u64>) {
        let read = |a: &AtomicU64| Some(a.load(Ordering::SeqCst)).filter(|&v| v != UNKNOWN);
        (read(&self.time.position_ms), read(&self.time.duration_ms))
    }
}

impl Drop for Clip {
    fn drop(&mut self) {
        // Its thread ends when this goes; the engine stops with it.
        self.commands = None;
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// The clip's thread: sets the engine up, says whether that worked, then
/// serves requests and pictures until the clip is dropped.
fn run(
    bytes: Vec<u8>,
    texture: u64,
    output: Option<String>,
    inbox: Receiver<Command>,
    time: Arc<Time>,
    opened: mpsc::SyncSender<Result<(), String>>,
) {
    let _com = Com::enter();
    let (to_commands, from_engine) = mpsc::channel::<Note>();
    let set_up = (|| {
        let (device, on_gpu) = match crate::watching::decode::runner_device() {
            Some(device) if device.cast::<ID3D11VideoDevice>().is_ok() => (device, true),
            _ => (own_device()?, false),
        };
        protect(&device);
        let engine = Engine::new(&device, DXGI_FORMAT_NV12, output.as_deref(), to_commands)?;
        engine.load(&bytes)?;
        Ok::<_, String>((engine, Pictures::new(device, on_gpu)))
    })();
    drop(bytes);
    let (engine, mut pictures) = match set_up {
        Ok(ready) => {
            let _ = opened.send(Ok(()));
            ready
        }
        Err(e) => {
            log::warn!("Chat video: {e}");
            let _ = opened.send(Err(e));
            return;
        }
    };
    log::info!(
        "Chat video: Media Engine, pictures {}",
        if pictures.on_gpu {
            "on the runner's GPU"
        } else {
            "read back to memory"
        }
    );

    let mut playing = false;
    let mut failed = false;
    let mut shown = (0u32, 0u32);
    loop {
        loop {
            let command = match inbox.try_recv() {
                Ok(command) => command,
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => return,
            };
            // SAFETY (each call below): plain calls on the live engine.
            match command {
                Command::Play => {
                    playing = unsafe { engine.engine.Play() }.is_ok();
                }
                Command::Pause => {
                    let _ = unsafe { engine.engine.Pause() };
                    playing = false;
                }
                Command::Seek(ms) => {
                    let _ = unsafe { engine.engine.SetCurrentTime(ms as f64 / 1000.0) };
                }
                Command::Volume(volume) => {
                    // The engine takes 0 to 1; louder than recorded is not
                    // on offer here.
                    let _ = unsafe { engine.engine.SetVolume(volume.clamp(0.0, 1.0)) };
                }
            }
        }
        while let Ok(note) = from_engine.try_recv() {
            match note.event {
                EVENT_ENDED => {
                    playing = false;
                    emit(texture, ClipEventKind::Ended, 0, 0, String::new());
                }
                EVENT_ERROR if !failed => {
                    failed = true;
                    playing = false;
                    let (kind, reason) = failure(note.param1, note.param2);
                    log::warn!("Chat video failed: {reason}");
                    emit(texture, kind, 0, 0, reason);
                }
                _ => {}
            }
        }
        if !failed && engine.has_video() && engine.new_picture() {
            if let Some((stored, seen)) = engine.sizes() {
                match pictures.draw(&engine, texture, stored) {
                    Ok(()) => {
                        if seen != shown {
                            shown = seen;
                            emit(
                                texture,
                                ClipEventKind::PictureSize,
                                seen.0,
                                seen.1,
                                String::new(),
                            );
                        }
                    }
                    Err(e) if pictures.on_gpu => {
                        // Not tried on every GPU: read back instead from
                        // here on, which any device does.
                        log::warn!("Chat video: not drawn on the GPU ({e}); read back instead");
                        pictures.read_back_from_now();
                    }
                    Err(e) => log::warn!("Chat video: a picture was not drawn: {e}"),
                }
            }
        }
        // SAFETY: plain calls on the live engine.
        let (position, duration) =
            unsafe { (engine.engine.GetCurrentTime(), engine.engine.GetDuration()) };
        let ms = |s: f64| {
            if s.is_finite() && s >= 0.0 {
                (s * 1000.0) as u64
            } else {
                UNKNOWN
            }
        };
        time.position_ms.store(ms(position), Ordering::SeqCst);
        time.duration_ms.store(ms(duration), Ordering::SeqCst);
        thread::sleep(if playing { PLAYING_TICK } else { PAUSED_TICK });
    }
}

/// Where a clip's pictures go: the engine draws each into [scratch], made
/// at the picture's size, from where it is copied to the runner.
struct Pictures {
    device: ID3D11Device,
    context: ID3D11DeviceContext,
    on_gpu: bool,
    scratch: Option<ID3D11Texture2D>,
    /// GPU: the array the runner draws from, and which slices are lent.
    array: Option<ID3D11Texture2D>,
    busy: Arc<[AtomicBool; SLICES]>,
    /// Memory: the texture each picture is read back through.
    staging: Option<ID3D11Texture2D>,
    size: (u32, u32),
}

impl Pictures {
    fn new(device: ID3D11Device, on_gpu: bool) -> Pictures {
        // SAFETY: a plain call on a live device.
        let context = unsafe { device.GetImmediateContext() }.expect("a device has a context");
        Pictures {
            device,
            context,
            on_gpu,
            scratch: None,
            array: None,
            busy: Arc::new(Default::default()),
            staging: None,
            size: (0, 0),
        }
    }

    fn read_back_from_now(&mut self) {
        self.on_gpu = false;
        self.scratch = None;
        self.array = None;
        self.size = (0, 0);
    }

    fn texture(
        &self,
        (w, h): (u32, u32),
        slices: u32,
        bind: i32,
        staging: bool,
    ) -> Result<ID3D11Texture2D, String> {
        let desc = D3D11_TEXTURE2D_DESC {
            Width: w,
            Height: h,
            MipLevels: 1,
            ArraySize: slices,
            Format: DXGI_FORMAT_NV12,
            SampleDesc: DXGI_SAMPLE_DESC {
                Count: 1,
                Quality: 0,
            },
            Usage: if staging {
                D3D11_USAGE_STAGING
            } else {
                D3D11_USAGE_DEFAULT
            },
            BindFlags: bind as u32,
            CPUAccessFlags: if staging {
                D3D11_CPU_ACCESS_READ.0 as u32
            } else {
                0
            },
            MiscFlags: 0,
        };
        let mut texture = None;
        // SAFETY: a plain call with a local description and out-pointer.
        unsafe { self.device.CreateTexture2D(&desc, None, Some(&mut texture)) }
            .map_err(|e| format!("no {w}x{h} NV12 texture: {e}"))?;
        texture.ok_or_else(|| "no texture".to_string())
    }

    /// Has the engine draw its current picture, [stored] in size, and hands
    /// it to [clip]'s slot.
    fn draw(&mut self, engine: &Engine, clip: u64, stored: (u32, u32)) -> Result<(), String> {
        // NV12 comes in whole pairs of pixels.
        let size = ((stored.0 + 1) & !1, (stored.1 + 1) & !1);
        if size != self.size || self.scratch.is_none() {
            self.scratch = Some(self.texture(size, 1, D3D11_BIND_RENDER_TARGET.0, false)?);
            if self.on_gpu {
                // A new array, so the slices lent of the old are not reused:
                // they hold it until handed back.
                self.array =
                    Some(self.texture(size, SLICES as u32, D3D11_BIND_SHADER_RESOURCE.0, false)?);
                self.busy = Arc::new(Default::default());
            } else {
                self.staging = Some(self.texture(size, 1, 0, true)?);
            }
            self.size = size;
        }
        let scratch = self.scratch.as_ref().expect("made above");
        let whole = RECT {
            left: 0,
            top: 0,
            right: size.0 as i32,
            bottom: size.1 as i32,
        };
        // SAFETY: a plain call; the texture and rectangle outlive it.
        unsafe {
            engine
                .engine
                .TransferVideoFrame(scratch, None, &whole, None)
        }
        .map_err(|e| format!("the engine did not draw it: {e}"))?;
        let matrix = matrix_for(stored.1);
        if self.on_gpu {
            let array = self.array.as_ref().expect("made with the scratch");
            let Some(slice) = (0..SLICES).find(|&s| !self.busy[s].load(Ordering::SeqCst)) else {
                return Ok(()); // all lent: this one is skipped
            };
            // SAFETY: both textures are live and NV12 of one size; the copy
            // is queued on the context the runner draws with, so it lands
            // before the runner reads the slice.
            unsafe {
                self.context
                    .CopySubresourceRegion(array, slice as u32, 0, 0, 0, scratch, 0, None)
            };
            self.busy[slice].store(true, Ordering::SeqCst);
            frames::deliver(
                clip,
                SlicePicture {
                    array: array.clone(),
                    slice,
                    busy: self.busy.clone(),
                    width: stored.0,
                    height: stored.1,
                    matrix,
                },
            );
        } else {
            let staging = self.staging.as_ref().expect("made with the scratch");
            frames::deliver(
                clip,
                self.read_back(staging, scratch, size, stored, matrix)?,
            );
        }
        Ok(())
    }

    /// The picture copied to memory as I420.
    fn read_back(
        &self,
        staging: &ID3D11Texture2D,
        scratch: &ID3D11Texture2D,
        (cw, ch): (u32, u32),
        (w, h): (u32, u32),
        matrix: u32,
    ) -> Result<MemoryPicture, String> {
        let mut mapped = D3D11_MAPPED_SUBRESOURCE::default();
        // SAFETY: both textures live and alike; the mapping is read within
        // its pitch and height and unmapped before returning.
        unsafe {
            self.context.CopyResource(staging, scratch);
            self.context
                .Map(staging, 0, D3D11_MAP_READ, 0, Some(&mut mapped))
                .map_err(|e| format!("the picture could not be read: {e}"))?;
            let pitch = mapped.RowPitch as usize;
            let base = mapped.pData as *const u8;
            let luma = std::slice::from_raw_parts(base, pitch * ch as usize);
            let chroma =
                std::slice::from_raw_parts(base.add(pitch * ch as usize), pitch * ch as usize / 2);
            let picture = MemoryPicture::from_nv12(luma, chroma, pitch, (cw, ch), (w, h), matrix);
            self.context.Unmap(staging, 0);
            Ok(picture)
        }
    }
}

/// The engine draws BT.709 for HD and BT.601 below it, limited range, as
/// Media Foundation's video processor does by default.
fn matrix_for(height: u32) -> u32 {
    if height >= 720 {
        1
    } else {
        0
    }
}

/// A picture in a slice of the clip's array, lent to the runner; the slice
/// is free again once it is handed back.
struct SlicePicture {
    array: ID3D11Texture2D,
    slice: usize,
    busy: Arc<[AtomicBool; SLICES]>,
    width: u32,
    height: u32,
    matrix: u32,
}

// SAFETY: the texture is only read by the runner, under the device's lock,
// and released from whichever thread lets the picture go, which COM allows of
// a D3D11 object.
unsafe impl Send for SlicePicture {}

impl Picture for SlicePicture {
    fn planes(&self) -> WatchPlanes {
        WatchPlanes {
            kind: IN_D3D11,
            matrix: self.matrix,
            texture: self.array.as_raw(),
            slice: self.slice as u32,
            ..WatchPlanes::sized(self.width, self.height)
        }
    }
}

impl Drop for SlicePicture {
    fn drop(&mut self) {
        self.busy[self.slice].store(false, Ordering::SeqCst);
    }
}

/// A picture read back into memory, as I420.
struct MemoryPicture {
    y: Vec<u8>,
    u: Vec<u8>,
    v: Vec<u8>,
    width: u32,
    height: u32,
    matrix: u32,
}

impl MemoryPicture {
    /// From NV12 rows [pitch] apart, coded at [coded], shown at [shown].
    fn from_nv12(
        luma: &[u8],
        chroma: &[u8],
        pitch: usize,
        coded: (u32, u32),
        shown: (u32, u32),
        matrix: u32,
    ) -> MemoryPicture {
        let (w, h) = (shown.0 as usize, shown.1 as usize);
        let (cw, ch) = ((w + 1) / 2, (h + 1) / 2);
        debug_assert!(shown.0 <= coded.0 && shown.1 <= coded.1);
        let mut y = Vec::with_capacity(w * h);
        for row in 0..h {
            y.extend_from_slice(&luma[row * pitch..row * pitch + w]);
        }
        let mut u = Vec::with_capacity(cw * ch);
        let mut v = Vec::with_capacity(cw * ch);
        for row in 0..ch {
            let line = &chroma[row * pitch..row * pitch + cw * 2];
            for pair in line.chunks_exact(2) {
                u.push(pair[0]);
                v.push(pair[1]);
            }
        }
        MemoryPicture {
            y,
            u,
            v,
            width: shown.0,
            height: shown.1,
            matrix,
        }
    }
}

impl Picture for MemoryPicture {
    fn planes(&self) -> WatchPlanes {
        let half = (self.width + 1) / 2;
        WatchPlanes {
            y: self.y.as_ptr(),
            u: self.u.as_ptr(),
            v: self.v.as_ptr(),
            stride_y: self.width,
            stride_u: half,
            stride_v: half,
            matrix: self.matrix,
            ..WatchPlanes::sized(self.width, self.height)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::watching::frames::{rift_watch_frame_lock, rift_watch_frame_unlock};

    #[test]
    fn nv12_comes_out_as_i420() {
        // 4x2 coded, 3x2 shown, rows 6 apart.
        let luma = [1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0];
        let chroma = [10, 20, 11, 21, 0, 0];
        let p = MemoryPicture::from_nv12(&luma, &chroma, 6, (4, 2), (3, 2), 1);
        assert_eq!(p.y, [1, 2, 3, 5, 6, 7]);
        assert_eq!(p.u, [10, 11]);
        assert_eq!(p.v, [20, 21]);
        let planes = p.planes();
        assert_eq!((planes.width, planes.stride_y, planes.stride_u), (3, 3, 2));
    }

    static MARKS: AtomicU64 = AtomicU64::new(0);

    unsafe extern "C" fn mark(_texture: u64) {
        MARKS.fetch_add(1, Ordering::SeqCst);
    }

    /// Plays a real file from memory on a device made as the runner's is:
    ///
    /// ```text
    /// RIFT_CLIP_TEST=<a video> cargo test --release live_clip -- --ignored --nocapture
    /// ```
    ///
    /// `RIFT_CLIP_TEST_MEMORY=1` leaves the runner's place empty, so the
    /// pictures are read back to memory instead.
    #[test]
    #[ignore = "needs a video; see above"]
    fn live_clip_plays_seeks_and_closes() {
        let bytes = std::fs::read(std::env::var("RIFT_CLIP_TEST").unwrap()).unwrap();
        let _device = std::env::var("RIFT_CLIP_TEST_MEMORY")
            .is_err()
            .then(crate::watching::decode::RunnerDeviceInPlace::new);
        let texture = 9001;
        let started = std::time::Instant::now();
        super::super::open(bytes, texture, mark, None).unwrap();
        println!("opened in {:?}", started.elapsed());
        thread::sleep(Duration::from_millis(1000));
        let paused = MARKS.load(Ordering::SeqCst);
        println!("{paused} pictures while paused");
        assert!(paused >= 1, "the first picture is shown while paused");

        let mut planes = WatchPlanes::sized(0, 0);
        assert_eq!(unsafe { rift_watch_frame_lock(texture, &mut planes) }, 1);
        println!(
            "picture {}x{}, kind {}, matrix {}",
            planes.width, planes.height, planes.kind, planes.matrix
        );
        assert!(planes.width > 0);
        if planes.kind == IN_D3D11 {
            assert!(crate::watching::decode::slice_holds(&planes));
        } else {
            assert!(!planes.y.is_null() && !planes.v.is_null());
        }
        rift_watch_frame_unlock(texture, 1);

        super::super::with(texture, |c| c.play()).unwrap().unwrap();
        thread::sleep(Duration::from_millis(1000));
        let played = MARKS.load(Ordering::SeqCst) - paused;
        println!("{played} pictures in a second of play");
        assert!(played >= 10);

        super::super::with(texture, |c| c.seek(2500))
            .unwrap()
            .unwrap();
        thread::sleep(Duration::from_millis(300));
        let (position, duration) = super::super::with(texture, |c| c.time()).unwrap();
        println!("after the seek: {position:?} of {duration:?}");
        assert!(position.unwrap() >= 2500);

        super::super::close(texture);
        let after = MARKS.load(Ordering::SeqCst);
        thread::sleep(Duration::from_millis(300));
        assert_eq!(
            MARKS.load(Ordering::SeqCst),
            after,
            "nothing marked once closed"
        );
    }
}
