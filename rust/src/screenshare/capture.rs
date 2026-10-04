//! The capture thread: asks libwebrtc for a frame on every tick and hands
//! each one to the processing thread in `frames.rs`.
use super::frames::{self, SendableFrame};
use super::resolution::Size;
use super::sources;
#[cfg(target_os = "windows")]
use super::window_win;
use crate::api::screenshare::types::ScreenshareEvent;
use livekit::webrtc::desktop_capturer::{
    CaptureError, CaptureSource as Source, DesktopCaptureSourceType, DesktopCapturer,
    DesktopCapturerOptions,
};
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

/// Raw frames waiting for the processing thread. Two is one being converted
/// and one queued; anything older is stale and better dropped.
const FRAME_QUEUE: usize = 2;

/// How often a share waiting on a minimised window looks for it again.
#[cfg(target_os = "windows")]
const WAITING_POLL: Duration = Duration::from_millis(250);

pub(crate) struct CaptureRequest {
    pub source_type: DesktopCaptureSourceType,
    pub selected_index: Option<u32>,
    pub fps: u32,
    pub capture_cursor: bool,
    /// Told `true` when the shared window is minimised and `false` when it
    /// comes back. Windows only: a minimised window gives the capturer nothing
    /// new, so watchers are left with a still picture unless somebody says why.
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    pub on_minimised: Option<Box<dyn Fn(bool) + Send>>,
}

/// How the start of a capture went, as the capture thread learns it.
pub(crate) enum Progress {
    /// The window is minimised, so there is no frame until the user opens it
    /// again — which may be a while, and is theirs to choose. Windows only:
    /// elsewhere the desktop's own picker chooses the window.
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    Waiting,
    /// The first frame arrived, at this native size.
    FirstFrame(Size),
    /// There will never be a frame, and why.
    Failed(String),
}

pub(crate) type Started = UnboundedReceiver<Progress>;

pub(crate) enum Command {
    Terminate,
}

/// Where the processing thread finds the video source to feed, and the size
/// to scale into it. Frames flow only once one is [`attach`](Self::attach)ed,
/// which the session does after it has seen the native size and chosen an
/// output size — and again, with a new source, when the size is changed
/// during the share.
#[derive(Clone, Default)]
pub(crate) struct VideoSlot(Arc<Mutex<Slot>>);

#[derive(Default)]
struct Slot {
    feed: Option<(NativeVideoSource, Size)>,
    /// The size of the last frame captured, which a new source is sized for.
    native: Option<Size>,
}

impl VideoSlot {
    /// Feed `source` from the next frame on, scaled to `target`. The two must
    /// be set together: a source fed frames of another size is a black tile.
    pub(crate) fn attach(&self, source: NativeVideoSource, target: Size) {
        self.0.lock().unwrap().feed = Some((source, target));
    }

    /// The size the source is capturing at, once a frame has arrived.
    pub(crate) fn native(&self) -> Option<Size> {
        self.0.lock().unwrap().native
    }

    /// For the processing thread: note a frame's size, and say where it goes.
    pub(super) fn feed(&self, native: Size) -> Option<(NativeVideoSource, Size)> {
        let mut slot = self.0.lock().unwrap();
        slot.native = Some(native);
        slot.feed.clone()
    }
}

/// A running capture thread.
pub(crate) struct Capture {
    command_tx: Sender<Command>,
    /// Frames a second, read by the capture clock on every tick.
    fps: Arc<AtomicU32>,
    handle: JoinHandle<()>,
    slot: VideoSlot,
}

impl Capture {
    pub(crate) fn slot(&self) -> VideoSlot {
        self.slot.clone()
    }

    /// Change the capture clock. Takes effect from the next tick, or from
    /// the first one for a share still waiting on a minimised window.
    pub(crate) fn set_fps(&self, fps: u32) {
        self.fps.store(fps, Ordering::Relaxed);
    }

    /// Ask the thread to stop and wait for it. Blocks for at most one frame
    /// interval plus the capturer's own teardown.
    pub(crate) fn stop(self) {
        let _ = self.command_tx.send(Command::Terminate);
        if self.handle.join().is_err() {
            log::warn!("capture: thread panicked");
        }
    }
}

pub(crate) fn spawn(request: CaptureRequest) -> (Capture, Started) {
    let (command_tx, command_rx) = mpsc::channel();
    let (progress_tx, progress_rx) = unbounded_channel();
    let slot = VideoSlot::default();
    let feeds = slot.clone();
    let fps = Arc::new(AtomicU32::new(request.fps));
    let clock = fps.clone();
    let handle = thread::spawn(move || run(request, clock, progress_tx, feeds, command_rx));
    (
        Capture {
            command_tx,
            fps,
            handle,
            slot,
        },
        progress_rx,
    )
}

/// RAII guard that raises the Windows timer resolution to 1 ms and restores
/// it on drop, so `recv_timeout` does not sleep in ~15.6 ms steps on a machine
/// where nothing else has asked for a finer clock.
#[cfg(target_os = "windows")]
struct TimerResolutionGuard;

#[cfg(target_os = "windows")]
impl TimerResolutionGuard {
    fn new() -> Self {
        unsafe { windows::Win32::Media::timeBeginPeriod(1) };
        Self
    }
}

#[cfg(target_os = "windows")]
impl Drop for TimerResolutionGuard {
    fn drop(&mut self) {
        unsafe { windows::Win32::Media::timeEndPeriod(1) };
    }
}

fn run(
    request: CaptureRequest,
    fps: Arc<AtomicU32>,
    progress: UnboundedSender<Progress>,
    source_slot: VideoSlot,
    command_rx: mpsc::Receiver<Command>,
) {
    #[cfg(target_os = "windows")]
    let _timer = TimerResolutionGuard::new();

    let mut options = DesktopCapturerOptions::new(request.source_type);
    options.set_include_cursor(request.capture_cursor);
    let Some(mut capturer) = DesktopCapturer::new(options) else {
        let _ = progress.send(Progress::Failed(
            "Could not create a desktop capturer".to_string(),
        ));
        return;
    };

    let source = match find_source(&capturer, &request, &progress, &command_rx) {
        Ok(Some(source)) => source,
        // Stopped while waiting for the window.
        Ok(None) => return,
        Err(reason) => {
            let _ = progress.send(Progress::Failed(reason));
            return;
        }
    };
    log::info!("capture: source {}", source.title());
    #[cfg(target_os = "windows")]
    let window = (request.source_type == DesktopCaptureSourceType::Window).then(|| source.id());

    let (frame_tx, frame_rx) = mpsc::sync_channel::<SendableFrame>(FRAME_QUEUE);
    let _processing = frames::spawn_processing(frame_rx, source_slot);

    // Set when the source reports a permanent error, which for a window means
    // it was closed. The loop below watches this and ends the session.
    let source_lost = Arc::new(AtomicBool::new(false));
    let lost = Arc::clone(&source_lost);
    let mut first_frame = Some(progress);
    capturer.start_capture(Some(source), move |result| match result {
        Ok(frame) => {
            if let Some(tx) = first_frame.take() {
                let _ = tx.send(Progress::FirstFrame(Size {
                    width: frame.width() as u32,
                    height: frame.height() as u32,
                }));
            }
            // A full queue means the converter is behind; drop this one.
            let _ = frame_tx.try_send(SendableFrame(frame));
        }
        Err(CaptureError::Permanent) => {
            if let Some(tx) = first_frame.take() {
                let _ = tx.send(Progress::Failed("The selected source is gone".to_string()));
            }
            lost.store(true, Ordering::Relaxed);
        }
        // Transient: the next tick retries.
        Err(_) => {}
    });

    let interval = |fps: u32| Duration::from_secs_f64(1.0 / f64::from(fps.max(1)));
    let mut rate = fps.load(Ordering::Relaxed);
    let mut frame_interval = interval(rate);
    let mut next_frame = Instant::now() + frame_interval;
    #[cfg(target_os = "windows")]
    let mut minimised = false;
    loop {
        let timeout = next_frame.saturating_duration_since(Instant::now());
        match command_rx.recv_timeout(timeout) {
            Ok(Command::Terminate) | Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {
                capturer.capture_frame();
                #[cfg(target_os = "windows")]
                if window.is_some_and(window_win::closed) {
                    source_lost.store(true, Ordering::Relaxed);
                }
                if source_lost.load(Ordering::Relaxed) {
                    log::info!("capture: source closed, ending the share");
                    crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
                    break;
                }
                #[cfg(target_os = "windows")]
                if let (Some(id), Some(report)) = (window, request.on_minimised.as_ref()) {
                    let now = window_win::minimised(id);
                    if now != minimised {
                        minimised = now;
                        log::info!(
                            "capture: shared window {}",
                            if now { "minimised" } else { "restored" }
                        );
                        report(now);
                    }
                }
                let now_rate = fps.load(Ordering::Relaxed);
                if now_rate != rate {
                    log::info!("capture: now {now_rate} fps");
                    rate = now_rate;
                    frame_interval = interval(rate);
                }
                next_frame += frame_interval;
                // Far behind: restart the clock rather than fire a burst of
                // catch-up captures.
                if Instant::now() > next_frame {
                    next_frame = Instant::now() + frame_interval;
                }
            }
        }
    }
    log::info!("capture: thread exiting");
}

/// The capturer's own entry for the chosen source, or `None` if the share
/// was stopped before there was one.
///
/// Found by id through the list the user picked from, so a window opening or
/// closing in the meantime cannot move the choice onto another one.
fn find_source(
    capturer: &DesktopCapturer,
    request: &CaptureRequest,
    progress: &UnboundedSender<Progress>,
    command_rx: &mpsc::Receiver<Command>,
) -> Result<Option<Source>, String> {
    let sources = capturer.get_source_list();
    // Nothing chosen: the Wayland portal, whose one source is what the user
    // picked in the desktop's own dialog.
    let Some(index) = request.selected_index else {
        return sources
            .into_iter()
            .next()
            .map(Some)
            .ok_or_else(|| "No capture sources available".to_string());
    };
    let Some(chosen) = sources::listed(request.source_type, index) else {
        return Err("Pick what to share again: the list has changed".to_string());
    };
    if let Some(source) = sources.into_iter().find(|source| source.id() == chosen.id) {
        return Ok(Some(source));
    }

    #[cfg(target_os = "windows")]
    if request.source_type == DesktopCaptureSourceType::Window && window_win::minimised(chosen.id) {
        return wait_for_window(capturer, request, &chosen, progress, command_rx);
    }
    let _ = (progress, command_rx);
    Err(format!("“{}” is no longer there to share", chosen.title))
}

/// A minimised window is not in the capturer's list until it is back on
/// screen. It is not brought back for the user: they may well not be ready
/// to (reported Oct 4 2026), so the share waits — paused, which viewers are
/// told — for as long as it takes them, or until it is stopped or the window
/// closes.
#[cfg(target_os = "windows")]
fn wait_for_window(
    capturer: &DesktopCapturer,
    request: &CaptureRequest,
    chosen: &sources::Listed,
    progress: &UnboundedSender<Progress>,
    command_rx: &mpsc::Receiver<Command>,
) -> Result<Option<Source>, String> {
    log::info!("capture: waiting for the minimised window {}", chosen.title);
    let _ = progress.send(Progress::Waiting);
    if let Some(report) = request.on_minimised.as_ref() {
        report(true);
    }
    loop {
        match command_rx.recv_timeout(WAITING_POLL) {
            Ok(Command::Terminate) | Err(RecvTimeoutError::Disconnected) => return Ok(None),
            Err(RecvTimeoutError::Timeout) => {}
        }
        if window_win::closed(chosen.id) {
            log::info!("capture: the window closed while waiting, ending the share");
            crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
            return Err(format!("“{}” was closed", chosen.title));
        }
        let found = capturer
            .get_source_list()
            .into_iter()
            .find(|source| source.id() == chosen.id);
        if let Some(source) = found {
            log::info!("capture: the window is open, starting");
            if let Some(report) = request.on_minimised.as_ref() {
                report(false);
            }
            return Ok(Some(source));
        }
    }
}
