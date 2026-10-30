//! The capture thread: asks libwebrtc for a frame on every tick and hands
//! each one to the processing thread in `frames.rs`. A Wayland share runs
//! on Rift's own PipeWire stream instead where it can (`capture_pw.rs`).
#[cfg(target_os = "linux")]
use super::capture_pw;
use super::frames::{self, SendableFrame};
#[cfg(gpu_encoder)]
use super::gpu_feed::GpuFeed;
use super::latest::{self, Putter};
use super::resolution::Size;
use super::sources;
#[cfg(target_os = "windows")]
use super::window_win;
use crate::api::screenshare::types::ScreenshareEvent;
use livekit::webrtc::desktop_capturer::{
    CaptureError, CaptureSource as Source, DesktopCaptureSourceType, DesktopCapturer, DesktopFrame,
};
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

/// How often a share waiting on a minimised window looks for it again.
#[cfg(target_os = "windows")]
const WAITING_POLL: Duration = Duration::from_millis(250);

/// How long a share whose window went away looks for it before ending
/// ([`SharedWindow`]). A game that swaps its window for a new one is back well
/// inside it; a window somebody closed in a program still running ends the
/// share this much later than it used to.
#[cfg(target_os = "windows")]
const RECOVER_FOR: Duration = Duration::from_secs(10);

/// How long a stop waits for the capture thread to let go of the capturer.
/// Windows' capturer once never did, after a fullscreen game took its window
/// away (Oct 16 2026): the stop waited for ever, holding the share's lock,
/// and every Start after it waited behind that without a word.
const STOP_WAIT: Duration = Duration::from_secs(2);

pub(crate) struct CaptureRequest {
    pub source_type: DesktopCaptureSourceType,
    pub selected_index: Option<u32>,
    /// A window already picked in the desktop's own picker: see
    /// [`ScreenShareConfig::portal_choice`](crate::api::screenshare::types::ScreenShareConfig).
    pub portal_choice: Option<String>,
    /// [`ScreenShareConfig::gpu_capture`](crate::api::screenshare::types::ScreenShareConfig).
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    pub gpu_capture: bool,
    pub fps: u32,
    pub capture_cursor: bool,
    /// Told `true` when the shared window is minimised or has gone away, and
    /// `false` when it is back. Windows, and Wayland on Rift's own stream
    /// (`capture_pw.rs`): either way the capturer has nothing new, so
    /// watchers are left with a still picture unless somebody says why.
    #[cfg_attr(not(any(target_os = "windows", target_os = "linux")), allow(dead_code))]
    pub on_paused: Option<Box<dyn Fn(bool) + Send>>,
}

/// How the start of a capture went, as the capture thread learns it.
pub(crate) enum Progress {
    /// The window is minimised, so there is no frame until the user opens it
    /// again — which may be a while, and is theirs to choose. Windows only:
    /// elsewhere the desktop's own picker chooses the window.
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    Waiting,
    /// The desktop's picker is up, which waits on a person: the first frame
    /// is not due until [`Picked`](Self::Picked). Wayland on Rift's own
    /// stream only, where Rift runs the picker (`capture_pw.rs`).
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    Picking,
    /// The picker has its answer, and the first frame is due.
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    Picked,
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

/// What the processing thread hands each picture to.
#[derive(Clone)]
pub(crate) enum Feed {
    /// Raw pictures, which libwebrtc encodes.
    Raw(NativeVideoSource),
    /// Pictures for the GPU encoder, which feeds a pre-encoded source.
    #[cfg(gpu_encoder)]
    Gpu(Arc<GpuFeed>),
}

#[derive(Default)]
struct Slot {
    feed: Option<(Feed, Size)>,
    /// The size of the last frame captured, which a new source is sized for.
    native: Option<Size>,
}

impl VideoSlot {
    /// Send pictures to `feed` from the next frame on, scaled to `target`.
    /// The two must be set together: a source fed frames of another size is
    /// a black tile.
    pub(crate) fn attach(&self, feed: Feed, target: Size) {
        self.0.lock().unwrap().feed = Some((feed, target));
    }

    /// Stop sending pictures anywhere until the next [`attach`](Self::attach),
    /// which also lets go of a GPU encoder: the old one is closed before a new
    /// one opens, rather than two running at once on the same GPU.
    pub(crate) fn detach(&self) {
        self.0.lock().unwrap().feed = None;
    }

    /// The size the source is capturing at, once a frame has arrived.
    pub(crate) fn native(&self) -> Option<Size> {
        self.0.lock().unwrap().native
    }

    /// For the processing thread: note a frame's size, and say where it goes.
    pub(super) fn feed(&self, native: Size) -> Option<(Feed, Size)> {
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
    /// Hears once the thread has let go of everything, the capturer included.
    done: mpsc::Receiver<()>,
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

    /// Ask the thread to stop and wait for it, for at most [`STOP_WAIT`]. A
    /// capturer that does not let go in that time is left behind on its
    /// thread, and the encoder is closed from here instead, so that the share
    /// can end and another start.
    pub(crate) fn stop(self) {
        let _ = self.command_tx.send(Command::Terminate);
        match self.done.recv_timeout(STOP_WAIT) {
            Err(RecvTimeoutError::Timeout) => {
                log::warn!(
                    "capture: the capturer did not close in {} s; leaving it behind",
                    STOP_WAIT.as_secs()
                );
                self.slot.detach();
            }
            // Done, or the thread panicked before it could say so.
            Ok(()) | Err(RecvTimeoutError::Disconnected) => {
                if self.handle.join().is_err() {
                    log::warn!("capture: thread panicked");
                }
            }
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
    let (done_tx, done) = mpsc::channel();
    // The app's runtime, for the portal (`capture_pw::run`).
    #[cfg(target_os = "linux")]
    let runtime = tokio::runtime::Handle::try_current().ok();
    // Named, as each of a share's threads is, so a profile of the app can
    // tell what each stage costs.
    let handle = thread::Builder::new()
        .name("share-capture".to_string())
        .spawn(move || {
            // A Wayland share runs on Rift's own stream where it can.
            #[cfg(target_os = "linux")]
            let request = match capture_pw::run(
                request,
                runtime,
                &clock,
                &progress_tx,
                &feeds,
                &command_rx,
            ) {
                capture_pw::Handoff::Done => {
                    let _ = done_tx.send(());
                    return;
                }
                capture_pw::Handoff::Fallback(request) => request,
            };
            run(request, clock, progress_tx, feeds, command_rx);
            let _ = done_tx.send(());
        })
        .expect("no capture thread");
    (
        Capture {
            command_tx,
            fps,
            handle,
            done,
            slot,
        },
        progress_rx,
    )
}

/// RAII guard that raises the Windows timer resolution to 1 ms and restores
/// it on drop, so `recv_timeout` does not sleep in ~15.6 ms steps on a machine
/// where nothing else has asked for a finer clock.
///
/// It also asks Windows not to throttle the process while it shares. Windows
/// 11 slows a process it judges out of sight (EcoQoS) and may ignore its
/// finer clock, and a share runs while the game it shows covers Rift. In a
/// test process with no window, capture at 120 fps fell from about 106
/// pictures a second to 92 a few seconds in, and FFmpeg's Quick Sync sent
/// 88.7 fps; with throttling off, 119.8 and 118.3 (Oct 16 2026, an i7-12700H
/// laptop). On drop, Windows decides again.
#[cfg(target_os = "windows")]
struct TimerResolutionGuard;

#[cfg(target_os = "windows")]
impl TimerResolutionGuard {
    fn new() -> Self {
        use windows::Win32::System::Threading::{
            PROCESS_POWER_THROTTLING_EXECUTION_SPEED,
            PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION,
        };
        // Execution speed and the timer resolution both held unthrottled.
        set_power_throttling(
            PROCESS_POWER_THROTTLING_EXECUTION_SPEED
                | PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION,
        );
        unsafe { windows::Win32::Media::timeBeginPeriod(1) };
        Self
    }
}

#[cfg(target_os = "windows")]
impl Drop for TimerResolutionGuard {
    fn drop(&mut self) {
        unsafe { windows::Win32::Media::timeEndPeriod(1) };
        set_power_throttling(0);
    }
}

/// Turn off Windows' power throttling for this process in the ways `held`
/// names, leaving the rest to Windows: 0 hands all of it back.
#[cfg(target_os = "windows")]
fn set_power_throttling(held: u32) {
    use windows::Win32::System::Threading::{
        GetCurrentProcess, ProcessPowerThrottling, SetProcessInformation,
        PROCESS_POWER_THROTTLING_CURRENT_VERSION, PROCESS_POWER_THROTTLING_STATE,
    };
    let state = PROCESS_POWER_THROTTLING_STATE {
        Version: PROCESS_POWER_THROTTLING_CURRENT_VERSION,
        ControlMask: held,
        StateMask: 0,
    };
    // SAFETY: `state` is the structure this information class takes, and
    // outlives the call.
    let set = unsafe {
        SetProcessInformation(
            GetCurrentProcess(),
            ProcessPowerThrottling,
            std::ptr::from_ref(&state).cast(),
            std::mem::size_of::<PROCESS_POWER_THROTTLING_STATE>() as u32,
        )
    };
    if let Err(e) = set {
        log::info!("capture: power throttling left to Windows: {e}");
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

    let mut options = sources::options(request.source_type);
    options.set_include_cursor(request.capture_cursor);
    let Some(mut capturer) = DesktopCapturer::new(options) else {
        let _ = progress.send(Progress::Failed(
            "Could not create a desktop capturer".to_string(),
        ));
        return;
    };

    // A choice the portal saved is the capturer's to restore, and takes no
    // source from its list: selecting one would replace the choice.
    let restored = request
        .portal_choice
        .as_deref()
        .is_some_and(|token| capturer.select_restore_token(token));
    let source = if restored {
        log::info!("capture: the window picked in the desktop's picker");
        None
    } else {
        match find_source(&capturer, &request, &progress, &command_rx) {
            Ok(Some(source)) => Some(source),
            // Stopped while waiting for the window.
            Ok(None) => return,
            Err(reason) => {
                let _ = progress.send(Progress::Failed(reason));
                return;
            }
        }
    };
    if let Some(source) = &source {
        log::info!("capture: source {}", source.title());
    }
    #[cfg(target_os = "windows")]
    let mut window = source
        .as_ref()
        .filter(|_| request.source_type == DesktopCaptureSourceType::Window)
        .map(|source| SharedWindow::new(source.id(), source.title()));

    // One raw frame waits for the processing thread, a newer one replacing it.
    let (frame_tx, frame_rx) = latest::channel::<SendableFrame>();
    let _processing = frames::spawn_processing(frame_rx, source_slot);
    let signals = Signals {
        frames: Arc::new(frame_tx),
        lost: Arc::new(AtomicBool::new(false)),
        arrived: Arc::new(AtomicBool::new(false)),
    };
    capturer.start_capture(source, signals.callback(Some(progress)));

    let interval = |fps: u32| Duration::from_secs_f64(1.0 / f64::from(fps.max(1)));
    let mut rate = fps.load(Ordering::Relaxed);
    let mut frame_interval = interval(rate);
    let mut next_frame = Instant::now() + frame_interval;
    loop {
        let timeout = next_frame.saturating_duration_since(Instant::now());
        match command_rx.recv_timeout(timeout) {
            Ok(Command::Terminate) | Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {
                capturer.capture_frame();
                #[cfg(target_os = "windows")]
                let ended = match window.as_mut() {
                    Some(window) => {
                        window.ended(&mut capturer, &signals, request.on_paused.as_deref())
                    }
                    None => signals.lost.load(Ordering::Relaxed),
                };
                #[cfg(not(target_os = "windows"))]
                let ended = signals.lost.load(Ordering::Relaxed);
                if ended {
                    log::info!("capture: source closed, ending the share");
                    crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
                    break;
                }
                let now_rate = fps.load(Ordering::Relaxed);
                if now_rate != rate {
                    log::info!("capture: now {now_rate} fps");
                    rate = now_rate;
                    frame_interval = interval(rate);
                }
                next_frame += frame_interval;
                // Behind: restart the clock rather than fire a burst of
                // catch-up captures, from now and not an interval on. A
                // capture a little slower than the interval (a 2K window
                // over X11 at 120 fps: 8.9 ms of 8.3) used to wait out a
                // whole interval after it, which halved the rate.
                if Instant::now() > next_frame {
                    next_frame = Instant::now();
                }
            }
        }
    }
    log::info!("capture: thread exiting");
}

/// What the capture thread learns from the capturer's results, shared with
/// each callback it is handed.
#[derive(Clone)]
struct Signals {
    /// The processing thread's mailbox. Its loop ends once the last callback
    /// holding it is gone.
    frames: Arc<Putter<SendableFrame>>,
    /// The source reported a permanent error, which for a window means it
    /// was closed or Windows stopped capturing it.
    lost: Arc<AtomicBool>,
    /// A picture has come in.
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    arrived: Arc<AtomicBool>,
}

impl Signals {
    /// A callback for the capturer, which tells `first_frame` how the first
    /// result went.
    fn callback(
        &self,
        mut first_frame: Option<UnboundedSender<Progress>>,
    ) -> impl FnMut(Result<DesktopFrame, CaptureError>) + Send + 'static {
        let signals = self.clone();
        move |result| match result {
            // What Windows' capturer gives as a window closes, which is no
            // picture of anything (seen Oct 16 2026).
            Ok(frame) if frame.width() < 2 || frame.height() < 2 => {}
            Ok(frame) => {
                if let Some(tx) = first_frame.take() {
                    let _ = tx.send(Progress::FirstFrame(Size {
                        width: frame.width() as u32,
                        height: frame.height() as u32,
                    }));
                }
                signals.arrived.store(true, Ordering::Relaxed);
                // One still waiting means the converter is behind; it is
                // dropped for this newer one.
                let _ = signals.frames.put(SendableFrame(frame));
            }
            Err(CaptureError::Permanent) => {
                if let Some(tx) = first_frame.take() {
                    let _ = tx.send(Progress::Failed("The selected source is gone".to_string()));
                }
                signals.lost.store(true, Ordering::Relaxed);
            }
            // Transient: the next tick retries.
            Err(_) => {}
        }
    }
}

/// The window a share shows, followed through what a game does to it.
///
/// A fullscreen game can take its window away while it runs. Red Dead
/// Redemption 2 did seven seconds into a share (reported Oct 16 2026), and
/// the share ended under a game still being played. So a window that goes is
/// looked for again — the same one once it can be captured, or else the one
/// window of the same program with the same title — while viewers are told
/// the share is paused. It ends once the program has quit, or after
/// [`RECOVER_FOR`].
#[cfg(target_os = "windows")]
struct SharedWindow {
    id: u64,
    /// The program it belongs to, and its title: how a new window it was
    /// swapped for is known.
    owner: Option<u32>,
    title: String,
    minimised: bool,
    gone: Option<Gone>,
}

#[cfg(target_os = "windows")]
struct Gone {
    /// When it went, or when it was last seen minimised: bringing it back is
    /// then the user's to do, so that time does not count.
    since: Instant,
    looked: Option<Instant>,
    /// A window has been handed to the capturer again, which has not yet
    /// given a picture of it.
    retaken: bool,
}

#[cfg(target_os = "windows")]
impl SharedWindow {
    fn new(id: u64, title: String) -> Self {
        Self {
            id,
            owner: window_win::pid(id),
            title,
            minimised: false,
            gone: None,
        }
    }

    /// Whether the share is over, asked after each capture.
    fn ended(
        &mut self,
        capturer: &mut DesktopCapturer,
        signals: &Signals,
        report: Option<&(dyn Fn(bool) + Send)>,
    ) -> bool {
        let report = |paused: bool| {
            if let Some(report) = report {
                report(paused);
            }
        };
        let closed = window_win::closed(self.id);
        let failed = signals.lost.swap(false, Ordering::Relaxed);
        let now = Instant::now();
        if self.gone.is_none() {
            if !closed && !failed {
                self.follow_minimised(report);
                return false;
            }
            log::info!(
                "capture: the shared window {}; looking for it",
                if closed {
                    "closed"
                } else {
                    "stopped giving pictures"
                }
            );
            if !self.minimised {
                report(true);
            }
        }
        let gone = self.gone.get_or_insert(Gone {
            since: now,
            looked: None,
            retaken: false,
        });

        if gone.retaken {
            if !closed && !failed && signals.arrived.load(Ordering::Relaxed) {
                log::info!("capture: the shared window is back");
                self.gone = None;
                self.minimised = false;
                report(false);
                return false;
            }
            // Gone again before a picture of it came, or still waiting for one.
            gone.retaken = !(closed || failed);
        }
        if closed && !self.owner.is_some_and(window_win::running) {
            log::info!("capture: the shared window's program has quit");
            return true;
        }
        if !closed && window_win::minimised(self.id) {
            gone.since = now;
            return false;
        }
        if now.duration_since(gone.since) > RECOVER_FOR {
            log::info!(
                "capture: the shared window is not back after {} s",
                RECOVER_FOR.as_secs()
            );
            return true;
        }
        if gone.retaken
            || gone
                .looked
                .is_some_and(|at| now.duration_since(at) < WAITING_POLL)
        {
            return false;
        }
        gone.looked = Some(now);

        let listed = capturer.get_source_list();
        let known: Vec<(u64, Option<u32>, String)> = listed
            .iter()
            .map(|source| (source.id(), window_win::pid(source.id()), source.title()))
            .collect();
        let Some(source) = find_again(&known, self.id, self.owner, &self.title)
            .and_then(|at| listed.into_iter().nth(at))
        else {
            return false;
        };
        log::info!(
            "capture: sharing {} again",
            if source.id() == self.id {
                "the same window"
            } else {
                "the program's new window"
            }
        );
        self.id = source.id();
        gone.retaken = true;
        signals.arrived.store(false, Ordering::Relaxed);
        capturer.start_capture(Some(source), signals.callback(None));
        false
    }

    fn follow_minimised(&mut self, report: impl Fn(bool)) {
        let now = window_win::minimised(self.id);
        if now != self.minimised {
            self.minimised = now;
            log::info!(
                "capture: shared window {}",
                if now { "minimised" } else { "restored" }
            );
            report(now);
        }
    }
}

/// Which of the capturer's windows, listed as `(id, program, title)`, is the
/// shared window `id` again: itself, or else the one window of its program
/// with its title. Two alike could be either, so neither is taken.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn find_again(
    listed: &[(u64, Option<u32>, String)],
    id: u64,
    owner: Option<u32>,
    title: &str,
) -> Option<usize> {
    if let Some(at) = listed.iter().position(|(listed_id, ..)| *listed_id == id) {
        return Some(at);
    }
    let owner = owner?;
    let mut alike = listed
        .iter()
        .enumerate()
        .filter(|(_, (_, program, name))| *program == Some(owner) && name == title);
    let (at, _) = alike.next()?;
    alike.next().is_none().then_some(at)
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
    if let Some(report) = request.on_paused.as_ref() {
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
            if let Some(report) = request.on_paused.as_ref() {
                report(false);
            }
            return Ok(Some(source));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(id: u64, program: u32, title: &str) -> (u64, Option<u32>, String) {
        (id, Some(program), title.to_string())
    }

    #[test]
    fn the_same_window_is_found_first() {
        let listed = [window(7, 1, "Game"), window(9, 1, "Game")];
        assert_eq!(find_again(&listed, 9, Some(1), "Game"), Some(1));
    }

    #[test]
    fn a_window_the_game_swapped_in_is_found_by_program_and_title() {
        let listed = [
            window(3, 2, "Game"),
            window(8, 1, "Launcher"),
            window(9, 1, "Game"),
        ];
        assert_eq!(find_again(&listed, 4, Some(1), "Game"), Some(2));
    }

    #[test]
    fn another_program_or_title_is_not_taken() {
        let listed = [window(3, 2, "Game"), window(8, 1, "Game - Settings")];
        assert_eq!(find_again(&listed, 4, Some(1), "Game"), None);
        assert_eq!(find_again(&listed, 4, None, "Game"), None);
    }

    #[test]
    fn two_alike_are_neither_taken() {
        let listed = [window(8, 1, "Game"), window(9, 1, "Game")];
        assert_eq!(find_again(&listed, 4, Some(1), "Game"), None);
    }

    /// A window that goes and comes back, on the desktop rather than in a
    /// test of its own: `RIFT_PROBE_TITLE` names a window of another program
    /// that closes, opens a new one with the same title at another size, and
    /// then quits, or with `RIFT_PROBE_LINGERS` closes that one too and runs
    /// on with no window (a PowerShell form does). Windows only, and from the
    /// desktop's session, where the windows are:
    ///
    /// RIFT_PROBE_TITLE=… cargo test --release window_swap -- --ignored
    #[cfg(target_os = "windows")]
    #[test]
    #[ignore]
    fn window_swap_is_followed_then_ends_with_its_program() {
        let _ = env_logger::builder()
            .is_test(true)
            .filter_level(log::LevelFilter::Info)
            .try_init();
        let title = std::env::var("RIFT_PROBE_TITLE").expect("RIFT_PROBE_TITLE");
        let index = sources::list(false)
            .into_iter()
            .find(|source| source.title == title)
            .expect("the probe window is listed")
            .index;
        let paused = Arc::new(Mutex::new(Vec::new()));
        let heard = paused.clone();
        let (capture, mut started) = spawn(CaptureRequest {
            source_type: DesktopCaptureSourceType::Window,
            selected_index: Some(index),
            portal_choice: None,
            gpu_capture: true,
            fps: 30,
            capture_cursor: false,
            on_paused: Some(Box::new(move |now| {
                heard.lock().unwrap().push((now, Instant::now()))
            })),
        });
        let first = loop {
            match started.try_recv() {
                Ok(Progress::FirstFrame(size)) => break size,
                Ok(Progress::Waiting) => {}
                Ok(Progress::Failed(reason)) => panic!("{reason}"),
                Err(_) => thread::sleep(Duration::from_millis(20)),
            }
        };
        let mut sizes = vec![first];
        let started = Instant::now();
        while !capture.handle.is_finished() && started.elapsed() < Duration::from_secs(60) {
            if let Some(size) = capture.slot().native() {
                if sizes.last() != Some(&size) {
                    log::info!("probe: now {}x{}", size.width, size.height);
                    sizes.push(size);
                }
            }
            thread::sleep(Duration::from_millis(50));
        }
        let ended = Instant::now();
        let paused = paused.lock().unwrap().clone();
        log::info!("probe: sizes {sizes:?}, paused {paused:?}");
        assert!(
            capture.handle.is_finished(),
            "the share outlived the program"
        );
        assert!(sizes.len() >= 2, "the new window was never captured");
        assert!(sizes.iter().all(|size| size.width > 1 && size.height > 1));
        // Paused while it was gone, back, and paused again before the end.
        let paused_now: Vec<bool> = paused.iter().map(|(now, _)| *now).collect();
        assert_eq!(paused_now, [true, false, true]);
        let last_pause = paused.last().unwrap().1;
        if std::env::var_os("RIFT_PROBE_LINGERS").is_some() {
            assert!(ended - last_pause >= RECOVER_FOR, "ended before giving up");
        } else {
            assert!(
                ended - last_pause < RECOVER_FOR,
                "waited for a program that quit"
            );
        }
        capture.stop();
    }

    #[test]
    fn a_stop_does_not_wait_for_a_capturer_that_never_lets_go() {
        let (command_tx, _command_rx) = mpsc::channel();
        let (done_tx, done) = mpsc::channel::<()>();
        // Holds its end of `done` and never finishes, as the capture thread
        // did inside Windows' capturer.
        let handle = thread::spawn(move || {
            let _done_tx = done_tx;
            loop {
                thread::park();
            }
        });
        let capture = Capture {
            command_tx,
            fps: Arc::new(AtomicU32::new(60)),
            handle,
            done,
            slot: VideoSlot::default(),
        };
        let started = Instant::now();
        capture.stop();
        assert!(started.elapsed() < STOP_WAIT + Duration::from_secs(1));
    }
}
