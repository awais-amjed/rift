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
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tokio::sync::oneshot;

/// Raw frames waiting for the processing thread. Two is one being converted
/// and one queued; anything older is stale and better dropped.
const FRAME_QUEUE: usize = 2;

/// How long a window restored from the taskbar gets to be back on screen,
/// and how often to look. A restore animates for a quarter of a second, and
/// a game coming back from minimised can take a few seconds to draw again.
const RESTORE_WAIT: Duration = Duration::from_secs(5);
const RESTORE_POLL: Duration = Duration::from_millis(100);

pub(crate) struct CaptureRequest {
    pub source_type: DesktopCaptureSourceType,
    pub selected_index: Option<u32>,
    pub fps: u32,
    pub max_height: u32,
    pub capture_cursor: bool,
    /// Told `true` when the shared window is minimised and `false` when it
    /// comes back. Windows only: a minimised window gives the capturer nothing
    /// new, so watchers are left with a still picture unless somebody says why.
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    pub on_minimised: Option<Box<dyn Fn(bool) + Send>>,
}

/// The first frame's native size, or why there will never be one.
pub(crate) type FirstFrame = oneshot::Receiver<Result<Size, String>>;

pub(crate) enum Command {
    Terminate,
}

/// A running capture thread. Frames flow only once a video source is
/// [`attach`](Self::attach)ed, which the session does after it has seen the
/// native size and chosen an output size.
pub(crate) struct Capture {
    command_tx: Sender<Command>,
    handle: JoinHandle<()>,
    source_slot: Arc<Mutex<Option<NativeVideoSource>>>,
}

impl Capture {
    pub(crate) fn attach(&self, source: NativeVideoSource) {
        *self.source_slot.lock().unwrap() = Some(source);
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

pub(crate) fn spawn(request: CaptureRequest) -> (Capture, FirstFrame) {
    let (command_tx, command_rx) = mpsc::channel();
    let (first_frame_tx, first_frame_rx) = oneshot::channel();
    let source_slot = Arc::new(Mutex::new(None));
    let slot = Arc::clone(&source_slot);
    let handle = thread::spawn(move || run(request, first_frame_tx, slot, command_rx));
    (
        Capture {
            command_tx,
            handle,
            source_slot,
        },
        first_frame_rx,
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
    first_frame: oneshot::Sender<Result<Size, String>>,
    source_slot: Arc<Mutex<Option<NativeVideoSource>>>,
    command_rx: mpsc::Receiver<Command>,
) {
    #[cfg(target_os = "windows")]
    let _timer = TimerResolutionGuard::new();

    let mut options = DesktopCapturerOptions::new(request.source_type);
    options.set_include_cursor(request.capture_cursor);
    let Some(mut capturer) = DesktopCapturer::new(options) else {
        let _ = first_frame.send(Err("Could not create a desktop capturer".to_string()));
        return;
    };

    let source = match find_source(&capturer, &request) {
        Ok(source) => source,
        Err(reason) => {
            let _ = first_frame.send(Err(reason));
            return;
        }
    };
    log::info!("capture: source {}", source.title());
    #[cfg(target_os = "windows")]
    let window = (request.source_type == DesktopCaptureSourceType::Window).then(|| source.id());

    let (frame_tx, frame_rx) = mpsc::sync_channel::<SendableFrame>(FRAME_QUEUE);
    let _processing = frames::spawn_processing(frame_rx, source_slot, request.max_height);

    // Set when the source reports a permanent error, which for a window means
    // it was closed. The loop below watches this and ends the session.
    let source_lost = Arc::new(AtomicBool::new(false));
    let lost = Arc::clone(&source_lost);
    let mut first_frame = Some(first_frame);
    capturer.start_capture(Some(source), move |result| match result {
        Ok(frame) => {
            if let Some(tx) = first_frame.take() {
                let _ = tx.send(Ok(Size {
                    width: frame.width() as u32,
                    height: frame.height() as u32,
                }));
            }
            // A full queue means the converter is behind; drop this one.
            let _ = frame_tx.try_send(SendableFrame(frame));
        }
        Err(CaptureError::Permanent) => {
            if let Some(tx) = first_frame.take() {
                let _ = tx.send(Err("The selected source is gone".to_string()));
            }
            lost.store(true, Ordering::Relaxed);
        }
        // Transient: the next tick retries.
        Err(_) => {}
    });

    let frame_interval = Duration::from_secs_f64(1.0 / request.fps as f64);
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

/// The capturer's own entry for the chosen source.
///
/// Found by id through the list the user picked from, so a window opening or
/// closing in the meantime cannot move the choice onto another one. A
/// minimised window is not in the capturer's list at all until it is back on
/// screen, so it is restored, and waited for.
fn find_source(capturer: &DesktopCapturer, request: &CaptureRequest) -> Result<Source, String> {
    let sources = capturer.get_source_list();
    // Nothing chosen: the Wayland portal, whose one source is what the user
    // picked in the desktop's own dialog.
    let Some(index) = request.selected_index else {
        return sources
            .into_iter()
            .next()
            .ok_or_else(|| "No capture sources available".to_string());
    };
    let Some(chosen) = sources::listed(request.source_type, index) else {
        return Err("Pick what to share again: the list has changed".to_string());
    };
    #[cfg(target_os = "windows")]
    if request.source_type == DesktopCaptureSourceType::Window && window_win::minimised(chosen.id)
    {
        log::info!("capture: restoring the minimised window {}", chosen.title);
        window_win::restore(chosen.id);
    }

    let deadline = Instant::now() + RESTORE_WAIT;
    let mut sources = sources;
    loop {
        if let Some(source) = sources.into_iter().find(|source| source.id() == chosen.id) {
            return Ok(source);
        }
        if Instant::now() >= deadline {
            return Err(format!("“{}” is no longer there to share", chosen.title));
        }
        thread::sleep(RESTORE_POLL);
        sources = capturer.get_source_list();
    }
}
