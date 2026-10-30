//! A Wayland share's PipeWire stream, read in Rift's FFmpeg library
//! (`native/ffenc/pipewire.c`, from OBS Studio's) so that a picture can reach
//! the GPU encoder as the compositor's DMA-BUF, never coming to the CPU
//! (`docs/gpu-codecs/STEP2_LINUX.md`). It lives there rather than in a crate
//! that links libpipewire into this library, which every Linux Rift would then
//! need to start: the FFmpeg library is opened at run time, and a computer it
//! does not load on shares through libwebrtc's capturer as before.
//!
//! A picture is the compositor's buffer, lent: it goes back when the
//! `PwPicture` is dropped, and the C side hands out at most two at a time.
use std::ffi::{c_char, c_void, CStr, CString};
use std::os::fd::AsRawFd;
use std::sync::OnceLock;

use super::encoder::{library, symbol};
use super::pixels::ByteOrder;
use super::portal::PortalSession;
use super::resolution::Size;

/// One DMA-BUF, field for field as `RiftDmabuf` in `ffenc.h`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct RiftDmabuf {
    pub width: i32,
    pub height: i32,
    pub crop_x: i32,
    pub crop_y: i32,
    pub crop_width: i32,
    pub crop_height: i32,
    pub drm_format: u32,
    pub modifier: u64,
    pub planes: i32,
    pub fds: [i32; 4],
    pub offsets: [u32; 4],
    pub strides: [u32; 4],
    pub transform: i32,
}

/// `RiftPwPicture`.
#[repr(C)]
struct RawPicture {
    dmabuf: RiftDmabuf,
    data: *const u8,
    len: usize,
    stride: i32,
    order: i32,
    buffers: i32,
    width: i32,
    height: i32,
    transform: i32,
    /// PipeWire's presentation time, on a clock the compositor chooses; the
    /// share stamps pictures with the wall clock instead, as every other.
    #[allow(dead_code)]
    pts_ns: i64,
    stream: *mut c_void,
    held: *mut c_void,
}

/// `RiftPwCallbacks`.
#[repr(C)]
struct Callbacks {
    user: *mut c_void,
    picture: extern "C" fn(*mut c_void, *const RawPicture),
    state: extern "C" fn(*mut c_void, i32, *const c_char),
}

/// `RiftPwBuffers`.
const RIFT_PW_DMABUF: i32 = 1;
const RIFT_PW_MEMORY: i32 = 2;

/// `RiftPwOrder`: red first.
const RIFT_PW_RGBX: i32 = 1;

type Open = unsafe extern "C" fn(
    i32,
    u32,
    i32,
    *const c_char,
    i32,
    i32,
    *const Callbacks,
    *mut c_char,
    usize,
) -> *mut c_void;

/// The library's stream functions, as `ffenc.h` declares them.
struct Api {
    open: Open,
    set_buffers: unsafe extern "C" fn(*mut c_void, i32),
    set_max_fps: unsafe extern "C" fn(*mut c_void, i32),
    drop_modifier: unsafe extern "C" fn(*mut c_void, u32, u64),
    release: unsafe extern "C" fn(*mut c_void, *mut c_void),
    close: unsafe extern "C" fn(*mut c_void),
}

fn api() -> Result<&'static Api, String> {
    static API: OnceLock<Result<Api, String>> = OnceLock::new();
    API.get_or_init(|| {
        let library = library()?;
        // SAFETY: each symbol is looked up with the type ffenc.h gives it,
        // in a library `library` checked is of this interface.
        unsafe {
            Ok(Api {
                open: symbol(library, "rift_pw_open")?,
                set_buffers: symbol(library, "rift_pw_set_buffers")?,
                set_max_fps: symbol(library, "rift_pw_set_max_fps")?,
                drop_modifier: symbol(library, "rift_pw_drop_modifier")?,
                release: symbol(library, "rift_pw_release")?,
                close: symbol(library, "rift_pw_close")?,
            })
        }
    })
    .as_ref()
    .map_err(Clone::clone)
}

/// Whether Rift's FFmpeg library is here with its stream, so a Wayland share
/// can run on it rather than on libwebrtc's capturer.
pub(crate) fn available() -> bool {
    api().is_ok()
}

/// The kind of buffer the stream asks the compositor for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PwBuffers {
    /// For the GPU encoder; memory buffers still come from a compositor
    /// that offers only those.
    DmaBuf,
    /// For the raw path, where the compositor reads the picture back.
    Memory,
}

impl PwBuffers {
    fn raw(self) -> i32 {
        match self {
            PwBuffers::DmaBuf => RIFT_PW_DMABUF,
            PwBuffers::Memory => RIFT_PW_MEMORY,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum PwEvent {
    Streaming,
    /// Also before the first picture.
    Paused,
    /// The stream is over: the source closed, or PipeWire failed.
    Ended(String),
}

/// A picture the compositor lent, given back when dropped.
pub(crate) struct PwPicture {
    raw: RawPicture,
    api: &'static Api,
}

// SAFETY: the buffer is this picture's until it is released, and the library
// takes a release from any thread. Shared, it is only read: nothing writes
// the buffer or its mapping while it is held, and the one release is in drop.
unsafe impl Send for PwPicture {}
unsafe impl Sync for PwPicture {}

impl PwPicture {
    /// Cropped and turned upright.
    pub fn size(&self) -> Size {
        Size {
            width: self.raw.width as u32,
            height: self.raw.height as u32,
        }
    }

    pub fn dmabuf(&self) -> Option<&RiftDmabuf> {
        (self.raw.buffers == RIFT_PW_DMABUF).then_some(&self.raw.dmabuf)
    }

    /// Rows from the crop's corner, their stride and byte order, not turned
    /// (`transform`). Whole rows where the buffer has them; a crop reaching
    /// the buffer's end has a last row only as wide as the crop.
    pub fn memory(&self) -> Option<(&[u8], u32, ByteOrder)> {
        if self.raw.buffers != RIFT_PW_MEMORY || self.raw.data.is_null() {
            return None;
        }
        // SAFETY: the library hands over `len` readable bytes at `data`,
        // mapped for as long as the buffer is held.
        let data = unsafe { std::slice::from_raw_parts(self.raw.data, self.raw.len) };
        let order = if self.raw.order == RIFT_PW_RGBX {
            ByteOrder::Rgbx
        } else {
            ByteOrder::Bgrx
        };
        Some((data, self.raw.stride as u32, order))
    }

    /// How the compositor turned the picture, as PipeWire's
    /// `SPA_META_TRANSFORMATION_*` says.
    pub fn transform(&self) -> i32 {
        self.raw.transform
    }
}

impl Drop for PwPicture {
    fn drop(&mut self) {
        // SAFETY: the picture's own buffer, released once.
        unsafe { (self.api.release)(self.raw.stream, self.raw.held) };
    }
}

/// What the callbacks reach, alive until the stream is closed.
struct Context {
    pictures: Box<dyn Fn(PwPicture) + Send>,
    events: Box<dyn Fn(PwEvent) + Send>,
    api: &'static Api,
}

extern "C" fn on_picture(user: *mut c_void, raw: *const RawPicture) {
    // SAFETY: `user` is the stream's context, alive until `rift_pw_close`,
    // after which no callback runs; `raw` is valid for this call.
    let context = unsafe { &*(user as *const Context) };
    let picture = PwPicture {
        raw: unsafe { std::ptr::read(raw) },
        api: context.api,
    };
    (context.pictures)(picture);
}

extern "C" fn on_state(user: *mut c_void, state: i32, error: *const c_char) {
    // SAFETY: as in `on_picture`; `error` is NUL-terminated or null.
    let context = unsafe { &*(user as *const Context) };
    let event = match state {
        0 => PwEvent::Streaming,
        1 => PwEvent::Paused,
        _ if error.is_null() => PwEvent::Ended("the stream ended".into()),
        _ => PwEvent::Ended(
            unsafe { CStr::from_ptr(error) }
                .to_string_lossy()
                .into_owned(),
        ),
    };
    (context.events)(event);
}

/// The stream of one portal session. Dropping it stops the stream; pictures
/// still held stay readable until they are dropped too.
pub(crate) struct PwStream {
    stream: *mut c_void,
    context: *mut Context,
    api: &'static Api,
}

// SAFETY: the library locks its stream for every call made on it.
unsafe impl Send for PwStream {}
unsafe impl Sync for PwStream {}

impl PwStream {
    /// Opens the stream on the session's node, at most `max_fps` pictures a
    /// second, each handed to `pictures` on PipeWire's thread, which must
    /// not hold it up: a picture it drops goes back to the compositor. DMA-BUFs are
    /// offered with the modifiers that import on `render_node`, and those that
    /// import only as external when `external_modifiers`, as NVENC's GL path
    /// can; `None` asks for memory buffers only. `events` runs on PipeWire's thread too, and
    /// must not hold it up.
    pub fn open(
        session: &PortalSession,
        max_fps: u32,
        render_node: Option<&str>,
        external_modifiers: bool,
        buffers: PwBuffers,
        pictures: impl Fn(PwPicture) + Send + 'static,
        events: Box<dyn Fn(PwEvent) + Send>,
    ) -> Result<PwStream, String> {
        let api = api()?;
        let render_node = render_node
            .map(CString::new)
            .transpose()
            .map_err(|e| e.to_string())?;
        let context = Box::into_raw(Box::new(Context {
            pictures: Box::new(pictures),
            events,
            api,
        }));
        let callbacks = Callbacks {
            user: context.cast(),
            picture: on_picture,
            state: on_state,
        };
        let mut error = [0 as c_char; 256];
        // SAFETY: the fd is the session's, which the library duplicates;
        // the callbacks' context lives until `rift_pw_close` returns.
        let stream = unsafe {
            (api.open)(
                session.fd.as_raw_fd(),
                session.node_id,
                max_fps.clamp(1, 360) as i32,
                render_node
                    .as_ref()
                    .map_or(std::ptr::null(), |n| n.as_ptr()),
                i32::from(external_modifiers),
                buffers.raw(),
                &callbacks,
                error.as_mut_ptr(),
                error.len(),
            )
        };
        if stream.is_null() {
            // SAFETY: the library refused, so nothing reaches the context.
            drop(unsafe { Box::from_raw(context) });
            // SAFETY: the library wrote a NUL-terminated reason.
            let error = unsafe { CStr::from_ptr(error.as_ptr()) };
            return Err(error.to_string_lossy().into_owned());
        }
        Ok(PwStream {
            stream,
            context,
            api,
        })
    }

    /// Asks for the other kind of buffer. Pictures already on their way
    /// still come in the old kind.
    pub fn set_buffers(&self, buffers: PwBuffers) {
        // SAFETY: an open stream.
        unsafe { (self.api.set_buffers)(self.stream, buffers.raw()) };
    }

    /// A new rate for the share, which the compositor sends at most.
    pub fn set_max_fps(&self, max_fps: u32) {
        // SAFETY: an open stream.
        unsafe { (self.api.set_max_fps)(self.stream, max_fps.clamp(1, 360) as i32) };
    }

    /// A modifier the encoder could not import: the compositor is asked for
    /// another, or memory buffers once none is left.
    pub fn drop_modifier(&self, drm_format: u32, modifier: u64) {
        // SAFETY: an open stream.
        unsafe { (self.api.drop_modifier)(self.stream, drm_format, modifier) };
    }
}

impl Drop for PwStream {
    fn drop(&mut self) {
        // SAFETY: closed once; no callback runs after it returns, so the
        // context can go.
        unsafe {
            (self.api.close)(self.stream);
            drop(Box::from_raw(self.context));
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::screenshare::latest;
    use crate::screenshare::portal::{self, PortalKind, PortalSession};
    use std::time::{Duration, Instant};

    /// The portal, restored from the token in the file `RIFT_PORTAL_TOKEN`
    /// names (seeded by `portal::tests::live_portal_seed_token`), which gets
    /// the renewed token back. The token is never printed. With
    /// `RIFT_PORTAL_WINDOW` set, a window picked by hand instead.
    pub(crate) fn screen() -> PortalSession {
        let _ = env_logger::builder()
            .is_test(true)
            .filter_level(log::LevelFilter::Info)
            .try_init();
        if std::env::var_os("RIFT_PORTAL_WINDOW").is_some() {
            return portal::tests::live_runtime()
                .block_on(portal::open(PortalKind::Window, None, true, false))
                .expect("the portal gives the window");
        }
        let file = std::env::var("RIFT_PORTAL_TOKEN").expect("RIFT_PORTAL_TOKEN");
        let token = std::fs::read_to_string(&file).unwrap();
        let session = portal::tests::live_runtime()
            .block_on(portal::open(
                PortalKind::Screen,
                Some(token.trim()),
                true,
                true,
            ))
            .expect("the portal restores the screen");
        if let Some(renewed) = &session.restore_token {
            std::fs::write(&file, renewed).unwrap();
        }
        session
    }

    pub(crate) fn render_node() -> String {
        std::env::var("RIFT_RENDER_NODE").unwrap_or_else(|_| "/dev/dri/renderD128".into())
    }

    fn open(session: &PortalSession, buffers: PwBuffers) -> (PwStream, latest::Taker<PwPicture>) {
        let (put, take) = latest::channel();
        let stream = PwStream::open(
            session,
            60,
            Some(&render_node()),
            false,
            buffers,
            move |picture| drop(put.put(picture)),
            Box::new(|event| log::info!("pipewire event: {event:?}")),
        )
        .expect("the stream opens");
        (stream, take)
    }

    /// Takes pictures for up to `within`, handing each to `check`, until
    /// `count` have come.
    fn take(
        pictures: &latest::Taker<PwPicture>,
        count: usize,
        within: Duration,
        mut check: impl FnMut(&PwPicture),
    ) -> usize {
        let start = Instant::now();
        let mut got = 0;
        while got < count && start.elapsed() < within {
            if let Some(picture) = pictures.take_timeout(Duration::from_millis(100)) {
                check(&picture);
                got += 1;
            }
        }
        got
    }

    // These need something moving on the screen (a test pattern playing),
    // since GNOME sends a picture only when the screen changes. Run with
    // stderr kept: PipeWire's own warnings go there.

    #[test]
    #[ignore]
    fn live_pw_stream_gives_dmabufs() {
        let session = screen();
        let (_stream, pictures) = open(&session, PwBuffers::DmaBuf);
        let screen = session.size;
        let got = take(&pictures, 60, Duration::from_secs(5), |picture| {
            assert!(picture.dmabuf().is_some(), "a memory picture");
            if let Some(screen) = screen {
                assert_eq!(picture.size(), screen);
            }
        });
        assert_eq!(got, 60, "{got} pictures in 5 s");
    }

    #[test]
    #[ignore]
    fn live_pw_stream_switches_to_memory() {
        let session = screen();
        let (stream, pictures) = open(&session, PwBuffers::DmaBuf);
        assert!(take(&pictures, 5, Duration::from_secs(5), |_| ()) == 5);
        stream.set_buffers(PwBuffers::Memory);
        // Pictures already on their way in DMA-BUFs come for a moment.
        let switched = Instant::now() + Duration::from_secs(1);
        while Instant::now() < switched {
            pictures.take_timeout(Duration::from_millis(50));
        }
        let got = take(&pictures, 30, Duration::from_secs(5), |picture| {
            let (data, stride, _) = picture.memory().expect("a memory picture");
            let size = picture.size();
            assert!(stride >= size.width * 4);
            assert!(data.len() >= (stride * (size.height - 1) + size.width * 4) as usize);
        });
        assert_eq!(got, 30);
    }

    /// A switch has PipeWire free the stream's buffers, the one a picture
    /// still holds among them: that picture's memory and fds stay its own
    /// until it is dropped.
    #[test]
    #[ignore]
    fn live_pw_stream_keeps_held_pictures_across_a_switch() {
        let session = screen();
        let (stream, pictures) = open(&session, PwBuffers::Memory);
        let held = pictures
            .take_timeout(Duration::from_secs(5))
            .expect("a picture");
        let (data, _, _) = held.memory().expect("a memory picture");
        stream.set_buffers(PwBuffers::DmaBuf);
        let switched = Instant::now() + Duration::from_secs(1);
        let mut dmabuf = None;
        while Instant::now() < switched || dmabuf.is_none() {
            assert!(
                Instant::now() < switched + Duration::from_secs(4),
                "no DMA-BUF"
            );
            if let Some(picture) = pictures.take_timeout(Duration::from_millis(50)) {
                if picture.dmabuf().is_some() {
                    dmabuf = Some(picture);
                }
            }
        }
        // Every byte still mapped.
        let sum = data.iter().fold(0u64, |sum, &byte| sum + u64::from(byte));
        log::info!("the held memory picture still reads ({sum})");
        drop(held);

        // The same files behind the fds after the switch, not closed and
        // their numbers taken by others.
        let file = |fd: i32| {
            // SAFETY: fstat into a zeroed stat.
            let mut stat: libc::stat = unsafe { std::mem::zeroed() };
            (unsafe { libc::fstat(fd, &mut stat) } == 0).then_some((stat.st_dev, stat.st_ino))
        };
        let dmabuf = dmabuf.unwrap();
        let planes = *dmabuf.dmabuf().unwrap();
        let fds = &planes.fds[..planes.planes as usize];
        let before: Vec<_> = fds.iter().map(|&fd| file(fd)).collect();
        assert!(before.iter().all(Option::is_some));
        stream.set_buffers(PwBuffers::Memory);
        let switched = Instant::now() + Duration::from_secs(1);
        while Instant::now() < switched {
            pictures.take_timeout(Duration::from_millis(50));
        }
        let after: Vec<_> = fds.iter().map(|&fd| file(fd)).collect();
        assert_eq!(before, after, "the held DMA-BUF's fds changed");
    }

    /// Some wlroots compositors share memory only red first. GStreamer's
    /// test pattern stands in for one: solid red, offered to PipeWire as
    /// RGBx alone. The stream takes it, says so, and the bytes are red's in
    /// that order, whether it asked for memory (the raw path) or for DMA-BUFs
    /// (a GPU feed, whose offer of both kinds is the larger). Needs
    /// GStreamer's PipeWire plugin (`pipewiresink`), not the portal or
    /// anything moving.
    #[test]
    #[ignore]
    fn live_pw_stream_takes_red_first_memory() {
        let _ = env_logger::builder()
            .is_test(true)
            .filter_level(log::LevelFilter::Info)
            .try_init();
        for buffers in [PwBuffers::Memory, PwBuffers::DmaBuf] {
            let (_source, session) = red_first_source();
            let (stream, pictures) = open(&session, buffers);
            let got = take(&pictures, 30, Duration::from_secs(5), |picture| {
                let (data, _, order) = picture.memory().expect("a memory picture");
                assert_eq!(order, ByteOrder::Rgbx);
                assert_eq!(&data[..3], &[255, 0, 0], "not red, red first");
                assert_eq!(
                    picture.size(),
                    Size {
                        width: 320,
                        height: 240
                    }
                );
            });
            drop(stream);
            assert_eq!(got, 30, "{got} pictures in 5 s, asking for {buffers:?}");
        }
    }

    /// GStreamer sending solid red as RGBx alone, and a session on its node.
    fn red_first_source() -> (Stopped, PortalSession) {
        const NAME: &str = "rift-red-first-test";
        let source = std::process::Command::new("gst-launch-1.0")
            .args([
                "-q",
                "videotestsrc",
                "pattern=solid-color",
                "foreground-color=0xffff0000",
                "is-live=true",
                "!",
                "video/x-raw,format=RGBx,width=320,height=240,framerate=30/1",
                "!",
                "pipewiresink",
                "mode=provide",
            ])
            .arg(format!(
                "stream-properties=props,node.name={NAME},media.class=Video/Source"
            ))
            .spawn()
            .expect("gst-launch-1.0");
        let source = Stopped(source);
        let node_id = (0..50)
            .find_map(|_| {
                std::thread::sleep(Duration::from_millis(100));
                node_named(NAME)
            })
            .expect("GStreamer's node");
        let runtime = std::env::var("XDG_RUNTIME_DIR").expect("XDG_RUNTIME_DIR");
        let socket = std::os::unix::net::UnixStream::connect(format!("{runtime}/pipewire-0"))
            .expect("PipeWire's socket");
        (source, PortalSession::of_node(socket.into(), node_id))
    }

    /// A process stopped when the test ends, failed or not.
    struct Stopped(std::process::Child);

    impl Drop for Stopped {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }

    /// The id of the PipeWire node called `name`, as `pw-dump` lists it.
    fn node_named(name: &str) -> Option<u32> {
        let dump = std::process::Command::new("pw-dump").output().ok()?;
        let objects: Vec<serde_json::Value> = serde_json::from_slice(&dump.stdout).ok()?;
        objects.iter().find_map(|object| {
            (object["info"]["props"]["node.name"] == name)
                .then(|| object["id"].as_u64())
                .flatten()
                .map(|id| id as u32)
        })
    }

    #[test]
    #[ignore]
    fn live_pw_stream_refused_dmabuf_gives_memory() {
        // SAFETY: the live tests run on one thread (`--test-threads=1`).
        unsafe { std::env::set_var("RIFT_PW_REFUSE_DMABUF", "1") };
        let session = screen();
        let (_stream, pictures) = open(&session, PwBuffers::DmaBuf);
        let got = take(&pictures, 30, Duration::from_secs(5), |picture| {
            assert!(picture.memory().is_some(), "a DMA-BUF picture");
        });
        unsafe { std::env::remove_var("RIFT_PW_REFUSE_DMABUF") };
        assert_eq!(got, 30);
    }

    /// What the library lets Rust hold at once (`MAX_HELD` in `pipewire.c`).
    const HELD_AT_MOST: usize = 4;

    /// A picture that comes while Rust holds all it may waits in the stream
    /// and arrives the moment Rust lets one go: on a still screen nothing
    /// newer comes to stand in for it. Needs nothing moving on the screen,
    /// unlike the tests above; GNOME's first pictures come in a burst, which
    /// fills Rust (with the library's old limit of two, the third never came).
    #[test]
    #[ignore]
    fn live_pw_stream_keeps_a_picture_that_came_while_rust_held_its_fill() {
        let session = screen();
        let (_stream, pictures) = open(&session, PwBuffers::DmaBuf);
        let mut held = Vec::new();
        while held.len() < HELD_AT_MOST {
            let picture = pictures.take_timeout(Duration::from_secs(5));
            held.push(picture.expect("a picture"));
        }
        // Long past the burst: nothing comes now but what waited.
        std::thread::sleep(Duration::from_millis(1300));
        let let_go = Instant::now();
        held.remove(0);
        let waited = pictures.take_timeout(Duration::from_secs(2));
        assert!(waited.is_some(), "no picture after letting go");
        let after = let_go.elapsed();
        assert!(
            after < Duration::from_millis(150),
            "the picture came {after:?} after letting go, not the one that waited"
        );
    }

    #[test]
    #[ignore]
    fn live_pw_stream_closes_holding_pictures() {
        let session = screen();
        let (stream, pictures) = open(&session, PwBuffers::DmaBuf);
        let mut held = Vec::new();
        while held.len() < 2 {
            if let Some(picture) = pictures.take_timeout(Duration::from_secs(5)) {
                held.push(picture);
            } else {
                panic!("no picture");
            }
        }
        drop(stream);
        drop(pictures);
        std::thread::sleep(Duration::from_millis(200));
        drop(held);
        drop(session);
    }
}
