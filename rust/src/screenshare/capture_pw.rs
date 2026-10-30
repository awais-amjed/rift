//! A Wayland share on Rift's own PipeWire stream (`docs/gpu-codecs/STEP2_LINUX.md`):
//! the portal from Rust (`portal.rs`), the stream in Rift's FFmpeg library
//! (`pw_stream.rs`), and each picture to the GPU encoder as the compositor's
//! DMA-BUF where the encoder takes one, or from memory for VP9 and NVENC.
//! When any of it refuses, the share runs on libwebrtc's capturer as before.
use super::capture::{CaptureRequest, Command, Feed, Progress, VideoSlot};
use super::encoder::{dmabuf_target, DmabufTarget};
use super::frames::{now_us, Converter};
use super::gpu_feed::{GpuFeed, Picture};
use super::latest::{self, Taker};
use super::portal::{self, PortalError, PortalKind, PortalSession};
use super::pw_stream::{self, PwBuffers, PwEvent, PwPicture, PwStream};
use super::resolution::Size;
use crate::api::screenshare::types::ScreenshareEvent;
use livekit::webrtc::desktop_capturer::DesktopCaptureSourceType;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, TryRecvError};
use std::sync::{Arc, Mutex, Weak};
use std::thread;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::UnboundedSender;

/// How often the capture thread looks for a stop, an ended stream or a new
/// rate. The pictures themselves never wait on it.
const POLL: Duration = Duration::from_millis(100);

/// How long the processing thread waits on a quiet compositor before it
/// sends the last memory picture again. A compositor sends a picture only
/// when the window changes, and KDE drew a covered window once and then
/// nothing (Oct 30, the KDE VM), where libwebrtc's capturer hands over its
/// last picture on every tick. WebRTC needs a picture to answer a viewer's
/// keyframe request with, and LiveKit's own keepalive runs at this rate too.
const REPEAT_EVERY: Duration = Duration::from_millis(100);

/// The repeat once a picture has been still for [`SETTLED_AFTER`]: by then
/// the quick repeats have sharpened it, and each one is an encode. The same
/// back-off libwebrtc's own still-screen mode makes (its zero-hertz idle
/// repeat), owner's call Oct 30.
const REPEAT_IDLE: Duration = Duration::from_secs(1);

/// How long after a new picture the repeats stay at [`REPEAT_EVERY`].
const SETTLED_AFTER: Duration = Duration::from_secs(2);

/// How long the stream stays paused before viewers are told the share is.
/// PipeWire pauses a stream for each renegotiation too (a switch of buffers,
/// a new rate, a resized window), for about 20 ms on GNOME (Oct 29), and
/// each one flashed "Paused" on viewers' tiles (found Oct 30 by the branch's
/// review).
const PAUSED_AFTER: Duration = Duration::from_secs(1);

/// Whether viewers are to be told the share is paused.
#[derive(Default)]
struct Pause {
    /// When the stream paused, while it is.
    since: Option<Instant>,
    /// Whether viewers were told.
    told: bool,
}

impl Pause {
    fn paused(&mut self, now: Instant) {
        self.since.get_or_insert(now);
    }

    /// The stream is back; says whether viewers were told it had paused.
    fn streaming(&mut self) -> bool {
        self.since = None;
        std::mem::take(&mut self.told)
    }

    /// Whether to tell viewers now: once, when a pause has lasted
    /// [`PAUSED_AFTER`].
    fn due(&mut self, now: Instant) -> bool {
        match self.since {
            Some(since) if !self.told && now >= since + PAUSED_AFTER => {
                self.told = true;
                true
            }
            _ => false,
        }
    }
}

/// A share's pauses and who hears of them, together so that what is heard
/// comes in the order it happened.
struct Pauses {
    pause: Pause,
    tell: Option<Box<dyn Fn(bool) + Send>>,
}

impl Pauses {
    fn streaming(&mut self) {
        if self.pause.streaming() {
            self.say(false);
        }
    }

    /// Asked by the capture thread on each [`POLL`].
    fn check(&mut self, now: Instant) {
        if self.pause.due(now) {
            self.say(true);
        }
    }

    fn say(&self, paused: bool) {
        if let Some(tell) = &self.tell {
            tell(paused);
        }
    }
}

/// When the last memory picture is due to be sent again.
struct Still {
    /// The kept picture's size; `None` once a DMA-BUF came after it, which
    /// the GPU encoder repeats itself.
    kept: Option<Size>,
    /// When it was last sent, or kept.
    since: Instant,
    /// When it came from the compositor.
    fresh: Instant,
}

impl Still {
    fn new(now: Instant) -> Self {
        Self {
            kept: None,
            since: now,
            fresh: now,
        }
    }

    /// A picture went to the feed, or was kept for one not there yet.
    fn noted(&mut self, kept: Option<Size>, now: Instant) {
        self.kept = kept;
        self.since = now;
        self.fresh = now;
    }

    /// The kept picture was sent again.
    fn repeated(&mut self, now: Instant) {
        self.since = now;
    }

    /// The size of the picture to send again, once it is due.
    fn due(&self, now: Instant) -> Option<Size> {
        let wait = if now.saturating_duration_since(self.fresh) < SETTLED_AFTER {
            REPEAT_EVERY
        } else {
            REPEAT_IDLE
        };
        self.kept
            .filter(|_| now.saturating_duration_since(self.since) >= wait)
    }
}

/// Whether this is a Wayland session, by the rule libwebrtc's own capturer
/// goes by, so a share Rift's stream refuses meets the capturer it would have
/// had anyway.
pub(crate) fn on_wayland() -> bool {
    on_wayland_from(
        std::env::var("WAYLAND_DISPLAY").ok().as_deref(),
        std::env::var("XDG_SESSION_TYPE").ok().as_deref(),
    )
}

fn on_wayland_from(wayland_display: Option<&str>, session_type: Option<&str>) -> bool {
    wayland_display.is_some_and(|display| !display.is_empty()) && session_type == Some("wayland")
}

/// The buffers `feed` can use: DMA-BUFs for a GPU encoder that imports them,
/// memory for the rest.
pub(crate) fn buffers_for(feed: &Feed) -> PwBuffers {
    wanted_buffers(match feed {
        Feed::Raw(_) => None,
        Feed::Gpu(gpu) => Some(gpu.takes_dmabuf()),
    })
}

/// The buffers a feed wants: `None` for the raw path, else whether its GPU
/// encoder takes a DMA-BUF.
fn wanted_buffers(gpu_takes_dmabuf: Option<bool>) -> PwBuffers {
    match gpu_takes_dmabuf {
        Some(true) => PwBuffers::DmaBuf,
        Some(false) | None => PwBuffers::Memory,
    }
}

/// The buffers a share opens on, before any feed has said what it wants: memory,
/// as a GPU feed takes a memory picture where the raw path cannot take a
/// DMA-BUF. Except on a screen NVIDIA's card draws, where GNOME sends no memory
/// picture at all while a fullscreen window fills the screen (seen Oct 30 on
/// GNOME 50), so a share begun over a game would never learn its size.
fn first_buffers(target: Option<&DmabufTarget>) -> PwBuffers {
    match target {
        Some(target) if target.external_modifiers => PwBuffers::DmaBuf,
        _ => PwBuffers::Memory,
    }
}

/// Whether a share goes on Rift's stream: under Wayland, unless the person has
/// turned it off in settings because a share looked wrong on their machine.
fn takes_rifts_stream(gpu_capture: bool, wayland: bool) -> bool {
    gpu_capture && wayland
}

/// How a share went on Rift's stream.
pub(super) enum Handoff {
    /// It ran, or failed in a way libwebrtc's capturer would too (the
    /// picker closed), and is over.
    Done,
    /// Not on Rift's stream: libwebrtc's capturer takes the request.
    Fallback(CaptureRequest),
}

/// Runs the share on Rift's stream until a stop or until the stream ends.
/// Portal calls go on `runtime`, the app's own: ashpd's one D-Bus connection
/// is driven by the runtime that opened it.
pub(super) fn run(
    mut request: CaptureRequest,
    runtime: Option<tokio::runtime::Handle>,
    fps: &AtomicU32,
    progress: &UnboundedSender<Progress>,
    slot: &VideoSlot,
    command_rx: &mpsc::Receiver<Command>,
) -> Handoff {
    if !takes_rifts_stream(request.gpu_capture, on_wayland()) {
        log::info!(
            "capture: GPU capture {}; libwebrtc's capturer",
            if request.gpu_capture {
                "needs Wayland"
            } else {
                "is off"
            }
        );
        return Handoff::Fallback(request);
    }
    let Some(runtime) = runtime else {
        log::info!("capture: no runtime for the portal; libwebrtc's capturer");
        return Handoff::Fallback(request);
    };
    if !pw_stream::available() {
        log::info!("capture: FFmpeg's library has no PipeWire stream; libwebrtc's capturer");
        return Handoff::Fallback(request);
    }
    let kind = match request.source_type {
        DesktopCaptureSourceType::Window => PortalKind::Window,
        _ => PortalKind::Screen,
    };
    let _ = progress.send(Progress::Picking);
    let opened = runtime.block_on(open_portal(
        kind,
        request.portal_choice.as_deref(),
        request.capture_cursor,
    ));
    let session = match opened {
        Ok(session) => session,
        Err(PortalError::Cancelled) => {
            let _ = progress.send(Progress::Failed(
                "The desktop's picker was closed without a choice".to_string(),
            ));
            return Handoff::Done;
        }
        Err(PortalError::Unavailable(reason)) => {
            log::info!("capture: the portal refused ({reason}); libwebrtc's capturer");
            return Handoff::Fallback(request);
        }
    };
    // Stopped while the picker was up.
    if !matches!(command_rx.try_recv(), Err(TryRecvError::Empty)) {
        return Handoff::Done;
    }
    let _ = progress.send(Progress::Picked);

    // Only Rift's stream reports a pause on Linux, so libwebrtc's capturer
    // loses nothing if the stream refuses.
    let pauses = Arc::new(Mutex::new(Pauses {
        pause: Pause::default(),
        tell: request.on_paused.take(),
    }));
    let arrived = Arc::new(AtomicBool::new(false));
    let ended = Arc::new(Mutex::new(None::<String>));
    let (put, pictures) = latest::channel::<PwPicture>();
    let first = Mutex::new(Some(progress.clone()));
    let seen = arrived.clone();
    let sink = move |picture: PwPicture| {
        if !seen.swap(true, Ordering::Relaxed) {
            if let Some(tx) = first.lock().unwrap().take() {
                let _ = tx.send(Progress::FirstFrame(picture.size()));
            }
        }
        // The picture it replaced, or this one once nobody takes them,
        // goes back to the compositor here.
        drop(put.put(picture));
    };
    let events = {
        let arrived = arrived.clone();
        let ended = ended.clone();
        let pauses = pauses.clone();
        Box::new(move |event| match event {
            PwEvent::Streaming => pauses.lock().unwrap().streaming(),
            // GNOME pauses a stream before its first picture too, which is
            // not a window anybody minimised.
            PwEvent::Paused if arrived.load(Ordering::Relaxed) => {
                pauses.lock().unwrap().pause.paused(Instant::now())
            }
            PwEvent::Paused => {}
            PwEvent::Ended(reason) => *ended.lock().unwrap() = Some(reason),
        })
    };
    let target = dmabuf_target();
    let render_node = target.as_ref().map(|target| target.render_node.as_str());
    // The feed is not attached until the first picture has said the size, and
    // then switches the stream to the buffers it wants.
    let opens_on = first_buffers(target.as_ref());
    let rate = fps.load(Ordering::Relaxed);
    let stream = match PwStream::open(
        &session,
        rate,
        render_node,
        target
            .as_ref()
            .is_some_and(|target| target.external_modifiers),
        opens_on,
        sink,
        events,
    ) {
        Ok(stream) => Arc::new(stream),
        Err(reason) => {
            log::warn!(
                "capture: Rift's PipeWire stream did not open ({reason}); libwebrtc's capturer"
            );
            return Handoff::Fallback(request);
        }
    };
    log::info!(
        "capture: on Rift's PipeWire stream ({}), DMA-BUFs for {}",
        session
            .size
            .map_or("size not given".to_string(), |s| format!(
                "{}x{}",
                s.width, s.height
            )),
        render_node.unwrap_or("no GPU (memory only)")
    );

    let processing = slot.clone();
    let controls = Arc::downgrade(&stream);
    let _processing = thread::Builder::new()
        .name("share-frames".to_string())
        .spawn(move || process(pictures, processing, controls, opens_on))
        .expect("no processing thread");

    watch(
        &stream, &session, &ended, &arrived, &pauses, fps, rate, progress, command_rx,
    );
    // The stream first, which closes the processing thread's mailbox; the
    // portal session after it.
    drop(stream);
    drop(session);
    log::info!("capture: thread exiting");
    Handoff::Done
}

/// The portal session for a share. A window's pick was made in Dart's
/// picker and is not kept again: GNOME forgets a pick once it is used, and
/// Dart forgets it on KDE (`WindowSharePortal.forget`). A screen is picked
/// here each time, as libwebrtc's capturer asked.
async fn open_portal(
    kind: PortalKind,
    window_choice: Option<&str>,
    cursor: bool,
) -> Result<PortalSession, PortalError> {
    // A live test restores the screen from the token `pw_stream`'s tests use.
    #[cfg(test)]
    if let (PortalKind::Screen, Some(file)) = (kind, std::env::var_os("RIFT_PORTAL_TOKEN")) {
        let token = std::fs::read_to_string(&file).unwrap();
        let session = portal::open(kind, Some(token.trim()), cursor, true).await?;
        if let Some(renewed) = &session.restore_token {
            std::fs::write(&file, renewed).unwrap();
        }
        return Ok(session);
    }
    portal::open(kind, window_choice, cursor, false).await
}

/// The capture thread's part once pictures flow: waits for a stop, ends the
/// share when the stream ends, tells viewers of a pause that lasts, and
/// passes on a new rate.
#[allow(clippy::too_many_arguments)]
fn watch(
    stream: &PwStream,
    session: &PortalSession,
    ended: &Mutex<Option<String>>,
    arrived: &AtomicBool,
    pauses: &Mutex<Pauses>,
    fps: &AtomicU32,
    mut rate: u32,
    progress: &UnboundedSender<Progress>,
    command_rx: &mpsc::Receiver<Command>,
) {
    loop {
        match command_rx.recv_timeout(POLL) {
            Ok(Command::Terminate) | Err(RecvTimeoutError::Disconnected) => return,
            Err(RecvTimeoutError::Timeout) => {}
        }
        let stream_ended = ended.lock().unwrap().take();
        if let Some(reason) = ended_by(stream_ended, session.closed()) {
            if arrived.load(Ordering::Relaxed) {
                log::info!("capture: the share is over ({reason}), ending it");
                crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
            } else {
                let _ = progress.send(Progress::Failed(reason));
            }
            return;
        }
        pauses.lock().unwrap().check(Instant::now());
        let now = fps.load(Ordering::Relaxed);
        if now != rate {
            log::info!("capture: now at most {now} fps");
            stream.set_max_fps(now);
            rate = now;
        }
    }
}

/// Why the desktop ended a share whose stream had not.
const SESSION_CLOSED: &str = "The desktop ended the share";

/// What ends a share on Rift's stream, if anything has: the stream ending,
/// or the portal session closing, which is all GNOME does when the shared
/// window closes (the stream only pauses). libwebrtc's capturer ends the
/// share on the same signal.
fn ended_by(stream_ended: Option<String>, session_closed: bool) -> Option<String> {
    stream_ended.or_else(|| session_closed.then(|| SESSION_CLOSED.to_string()))
}

/// The processing thread: each picture to its feed, in the buffers the feed
/// can use, asking the stream for those whenever the feed changes. The last
/// memory picture is kept and sent again while the compositor sends nothing
/// ([`REPEAT_EVERY`], then [`REPEAT_IDLE`]), the first one among them: it
/// says the size the feed is made for, so it comes before there is a feed.
/// And the newest picture of either kind is kept until a GPU feed takes it:
/// the rate gate can leave it out, and a new encoder or track has not had
/// it, and on a still screen nothing newer comes to take its place.
fn process(pictures: Taker<PwPicture>, slot: VideoSlot, stream: Weak<PwStream>, asked: PwBuffers) {
    let mut sender = Sender {
        slot,
        converter: Converter::new(),
        spare: Vec::new(),
        follow: Follow::new(stream, asked),
        still: Still::new(Instant::now()),
        taken: Taken::new(),
        warned_turned: false,
    };
    let mut newest: Option<Arc<PwPicture>> = None;
    loop {
        let Some(picture) = pictures.take_timeout(REPEAT_EVERY) else {
            if pictures.closed() {
                break;
            }
            if let Some(picture) = &newest {
                if sender.untaken(picture) {
                    sender.send(picture);
                    continue;
                }
            }
            let Some(size) = sender.still.due(Instant::now()) else {
                continue;
            };
            if let Some((feed, target)) = sender.slot.feed(size) {
                sender.follow.feed(&feed);
                sender.converter.send_kept(feed, target);
            }
            sender.still.repeated(Instant::now());
            continue;
        };
        // The older one goes back first, so the compositor is short one
        // buffer the less.
        drop(newest.take());
        let picture = Arc::new(picture);
        sender.taken.reset();
        sender.send(&picture);
        newest = Some(picture);
    }
}

/// What the processing thread hands pictures on with.
struct Sender {
    slot: VideoSlot,
    converter: Converter,
    spare: Vec<u8>,
    follow: Follow,
    still: Still,
    taken: Taken<GpuFeed>,
    warned_turned: bool,
}

impl Sender {
    /// Whether the feed attached now is a GPU feed that has not taken
    /// `picture`. Tells the stream of a new feed's buffers on the way, so a
    /// still screen's stream follows a fall back to VP9 too.
    fn untaken(&mut self, picture: &PwPicture) -> bool {
        let Some((feed, _)) = self.slot.feed(size_of(picture)) else {
            return false;
        };
        self.follow.feed(&feed);
        matches!(&feed, Feed::Gpu(gpu) if self.taken.wants(gpu))
    }

    /// `picture` to the feed for its size, or kept for one not there yet.
    fn send(&mut self, picture: &Arc<PwPicture>) {
        let size = size_of(picture);
        // Asked on every picture, because the session swaps in a new feed
        // when the size or the codec is changed mid-share.
        let feed = self.slot.feed(size);
        if let Some((feed, _)) = &feed {
            self.follow.feed(feed);
        }
        if let Some((data, stride, order)) = picture.memory() {
            if picture.transform() != 0 && !self.warned_turned {
                log::warn!("capture: the screen is turned, and a memory picture is sent as drawn");
                self.warned_turned = true;
            }
            let rows = whole_rows(data, stride, size.height, &mut self.spare);
            match feed {
                Some((feed, target)) => {
                    let gpu = match &feed {
                        Feed::Gpu(gpu) => Some(gpu.clone()),
                        Feed::Raw(_) => None,
                    };
                    let took = self.converter.send(rows, stride, order, size, feed, target);
                    if let (true, Some(gpu)) = (took, gpu) {
                        self.taken.by(&gpu);
                    }
                }
                None => self.converter.keep(rows, stride, order, size),
            }
            self.still.noted(self.converter.kept(), Instant::now());
            return;
        }
        match feed {
            Some((Feed::Gpu(gpu), target)) if gpu.takes_dmabuf() => {
                if gpu.send(Picture::DmaBuf(picture.clone()), target, now_us()) {
                    self.taken.by(&gpu);
                }
                self.converter.forget();
                self.still.noted(None, Instant::now());
            }
            // The raw path cannot read one: dropped while the switch to
            // memory lands.
            _ => {}
        }
    }
}

/// A picture's size as its feed is chosen by: a memory picture comes as the
/// compositor drew it, not turned.
fn size_of(picture: &PwPicture) -> Size {
    if picture.memory().is_some() {
        unturned(picture)
    } else {
        picture.size()
    }
}

/// Which feed has taken the newest picture. Held weakly, as [`Follow`]
/// holds its feed, so a new feed is never mistaken for one gone at the same
/// address.
struct Taken<T> {
    by: Weak<T>,
}

impl<T> Taken<T> {
    fn new() -> Self {
        Self { by: Weak::new() }
    }

    /// A newer picture, which no feed has had.
    fn reset(&mut self) {
        self.by = Weak::new();
    }

    fn by(&mut self, feed: &Arc<T>) {
        self.by = Arc::downgrade(feed);
    }

    /// Whether `feed` has yet to take the newest picture.
    fn wants(&self, feed: &Arc<T>) -> bool {
        !Weak::ptr_eq(&self.by, &Arc::downgrade(feed))
    }
}

/// What the stream is told as the feed changes: the buffers it can use, and
/// for a GPU feed, where its refused DMA-BUFs go.
struct Follow {
    stream: Weak<PwStream>,
    asked: PwBuffers,
    /// The GPU feed told. Held weakly, so a new feed is never mistaken for
    /// one gone at the same address.
    told: Weak<GpuFeed>,
}

impl Follow {
    fn new(stream: Weak<PwStream>, asked: PwBuffers) -> Self {
        Self {
            stream,
            asked,
            told: Weak::new(),
        }
    }

    fn feed(&mut self, feed: &Feed) {
        let wanted = buffers_for(feed);
        if wanted != self.asked {
            log::info!("capture: asking the compositor for {wanted:?} buffers");
            if let Some(stream) = self.stream.upgrade() {
                stream.set_buffers(wanted);
            }
            self.asked = wanted;
        }
        if let Feed::Gpu(gpu) = feed {
            if !Weak::ptr_eq(&self.told, &Arc::downgrade(gpu)) {
                let stream = self.stream.clone();
                gpu.on_import_failed(Box::new(move |drm_format, modifier| {
                    if let Some(stream) = stream.upgrade() {
                        stream.drop_modifier(drm_format, modifier);
                    }
                }));
                self.told = Arc::downgrade(gpu);
            }
        }
    }
}

/// `data` as `height` whole rows of `stride`, which libyuv's checks ask for.
/// A cropped picture's last row stops at the crop's edge, and the library
/// hands over whole rows only where the buffer has them; the rest is copied
/// into `spare`, padded.
fn whole_rows<'a>(data: &'a [u8], stride: u32, height: u32, spare: &'a mut Vec<u8>) -> &'a [u8] {
    let len = stride as usize * height as usize;
    if data.len() >= len {
        return data;
    }
    spare.clear();
    spare.extend_from_slice(data);
    spare.resize(len, 0);
    spare
}

/// A picture's size before the compositor's turn, which a quarter turn
/// (`SPA_META_TRANSFORMATION_90`, `_270` and their flips: the odd ones)
/// swaps.
fn unturned(picture: &PwPicture) -> Size {
    let size = picture.size();
    if picture.transform() & 1 == 1 {
        Size {
            width: size.height,
            height: size.width,
        }
    } else {
        size
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_feed_asks_for_the_buffers_it_can_use() {
        // Raw: libwebrtc reads the picture from memory.
        assert_eq!(wanted_buffers(None), PwBuffers::Memory);
        // VAAPI imports the DMA-BUF.
        assert_eq!(wanted_buffers(Some(true)), PwBuffers::DmaBuf);
        // A GPU encoder that takes no DMA-BUF reads from memory.
        assert_eq!(wanted_buffers(Some(false)), PwBuffers::Memory);
    }

    #[test]
    fn takes_rifts_stream_only_under_wayland_with_the_switch_on() {
        assert!(takes_rifts_stream(true, true));
        assert!(!takes_rifts_stream(false, true));
        assert!(!takes_rifts_stream(true, false));
        assert!(!takes_rifts_stream(false, false));
    }

    #[test]
    fn a_screen_nvidia_draws_opens_on_dmabufs() {
        let target = |external_modifiers| DmabufTarget {
            render_node: "/dev/dri/renderD128".to_string(),
            external_modifiers,
        };
        assert_eq!(first_buffers(Some(&target(true))), PwBuffers::DmaBuf);
        assert_eq!(first_buffers(Some(&target(false))), PwBuffers::Memory);
        assert_eq!(first_buffers(None), PwBuffers::Memory);
    }

    #[test]
    fn wayland_is_a_display_and_a_wayland_session() {
        assert!(on_wayland_from(Some("wayland-0"), Some("wayland")));
        assert!(!on_wayland_from(None, Some("wayland")));
        assert!(!on_wayland_from(Some(""), Some("wayland")));
        assert!(!on_wayland_from(Some("wayland-0"), Some("x11")));
        assert!(!on_wayland_from(Some("wayland-0"), None));
    }

    #[test]
    fn a_share_ends_with_its_stream_or_its_portal_session() {
        assert_eq!(ended_by(None, false), None);
        assert_eq!(
            ended_by(Some("unconnected".into()), false).as_deref(),
            Some("unconnected")
        );
        // GNOME closes the session when the shared window closes, and only
        // pauses the stream.
        assert_eq!(ended_by(None, true).as_deref(), Some(SESSION_CLOSED));
        assert_eq!(
            ended_by(Some("unconnected".into()), true).as_deref(),
            Some("unconnected")
        );
    }

    const SIZE: Size = Size {
        width: 1280,
        height: 754,
    };

    #[test]
    fn a_picture_that_came_before_its_feed_is_sent_once_there_is_one() {
        // KDE draws a covered window once and then nothing, and that one
        // picture comes before the feed it says the size for.
        let start = Instant::now();
        let mut still = Still::new(start);
        still.noted(Some(SIZE), start);
        assert_eq!(still.due(start + Duration::from_millis(99)), None);
        assert_eq!(still.due(start + REPEAT_EVERY), Some(SIZE));
    }

    #[test]
    fn a_still_picture_is_sent_again_while_nothing_new_comes() {
        let start = Instant::now();
        let mut still = Still::new(start);
        still.noted(Some(SIZE), start);
        let repeated = start + REPEAT_EVERY;
        still.repeated(repeated);
        assert_eq!(still.due(repeated + Duration::from_millis(50)), None);
        assert_eq!(still.due(repeated + REPEAT_EVERY), Some(SIZE));
        // Each new picture starts the wait again.
        let new = repeated + Duration::from_millis(150);
        still.noted(Some(SIZE), new);
        assert_eq!(still.due(new + Duration::from_millis(50)), None);
    }

    #[test]
    fn a_picture_still_for_two_seconds_is_sent_again_once_a_second() {
        let start = Instant::now();
        let mut still = Still::new(start);
        still.noted(Some(SIZE), start);
        let late = start + SETTLED_AFTER + Duration::from_millis(500);
        still.repeated(late);
        assert_eq!(still.due(late + REPEAT_EVERY), None);
        assert_eq!(still.due(late + Duration::from_millis(999)), None);
        assert_eq!(still.due(late + REPEAT_IDLE), Some(SIZE));
        // A new picture goes back to the quick repeats.
        let new = late + REPEAT_IDLE;
        still.noted(Some(SIZE), new);
        assert_eq!(still.due(new + REPEAT_EVERY), Some(SIZE));
    }

    #[test]
    fn nothing_is_repeated_from_memory_after_a_dmabuf() {
        // The GPU encoder repeats a DMA-BUF itself; a memory picture kept
        // from before it is older than what the viewer has.
        let start = Instant::now();
        let mut still = Still::new(start);
        still.noted(Some(SIZE), start);
        still.noted(None, start + Duration::from_millis(10));
        assert_eq!(still.due(start + Duration::from_secs(5)), None);
    }

    #[test]
    fn a_renegotiation_does_not_tell_viewers_the_share_is_paused() {
        // PipeWire pauses the stream for each renegotiation, for about 20 ms
        // on GNOME (switching to DMA-BUFs, Oct 29).
        let start = Instant::now();
        let mut pause = Pause::default();
        pause.paused(start);
        assert!(!pause.due(start + Duration::from_millis(100)));
        assert!(!pause.streaming());
        assert!(!pause.due(start + Duration::from_secs(5)));
    }

    #[test]
    fn a_pause_that_lasts_is_told_once_and_its_end_after_it() {
        let start = Instant::now();
        let mut pause = Pause::default();
        pause.paused(start);
        assert!(!pause.due(start + PAUSED_AFTER - Duration::from_millis(1)));
        assert!(pause.due(start + PAUSED_AFTER));
        assert!(!pause.due(start + PAUSED_AFTER * 2));
        assert!(pause.streaming());
        assert!(!pause.streaming());
    }

    #[test]
    fn the_newest_picture_is_offered_to_each_feed_until_one_takes_it() {
        let feed = Arc::new(1);
        let mut taken = Taken::new();
        // Left out by the rate gate: offered again on the next tick.
        assert!(taken.wants(&feed));
        taken.by(&feed);
        assert!(!taken.wants(&feed));
        // A new encoder, or a new track's, has not had it.
        let new = Arc::new(2);
        assert!(taken.wants(&new));
        // Nor has anyone a newer picture.
        taken.reset();
        assert!(taken.wants(&feed));
    }

    #[test]
    fn a_cropped_picture_reaches_the_converter_in_whole_rows() {
        // Three rows of a 16-byte stride, cropped to 8 bytes wide: the last
        // row stops at the crop's edge, short of the stride.
        let tight: Vec<u8> = (0..40).collect();
        let mut spare = Vec::new();
        let rows = whole_rows(&tight, 16, 3, &mut spare);
        assert_eq!(rows.len(), 48);
        assert_eq!(&rows[..40], &tight[..]);
        // Whole rows already: handed on as they are, not copied.
        let whole = vec![7u8; 48];
        let mut spare = Vec::new();
        assert!(std::ptr::eq(
            whole_rows(&whole, 16, 3, &mut spare),
            &whole[..]
        ));
        assert!(spare.is_empty());
    }
}
