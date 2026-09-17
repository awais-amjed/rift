//! The capture thread: asks libwebrtc for a frame on every tick and hands
//! each one to the processing thread in `frames.rs`.
use super::frames::{self, SendableFrame};
use super::resolution::Size;
use crate::api::screenshare::types::{CaptureSource, ScreenshareEvent};
use crate::sharing::audio;
use livekit::webrtc::desktop_capturer::{
    CaptureError, DesktopCaptureSourceType, DesktopCapturer, DesktopCapturerOptions,
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

pub(crate) struct CaptureRequest {
    pub source_type: DesktopCaptureSourceType,
    pub selected_index: Option<u32>,
    pub fps: u32,
    pub max_height: u32,
    pub capture_cursor: bool,
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

    let sources = capturer.get_source_list();
    let index = request
        .selected_index
        .map(|i| i as usize)
        .filter(|i| *i < sources.len())
        .unwrap_or(0);
    let Some(source) = sources.get(index).cloned() else {
        let _ = first_frame.send(Err("No capture sources available".to_string()));
        return;
    };
    log::info!("capture: source [{index}] {}", source.title());

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
    loop {
        let timeout = next_frame.saturating_duration_since(Instant::now());
        match command_rx.recv_timeout(timeout) {
            Ok(Command::Terminate) | Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {
                capturer.capture_frame();
                if source_lost.load(Ordering::Relaxed) {
                    log::info!("capture: source closed, ending the share");
                    crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
                    break;
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

/// Screens or windows, in the order their indexes refer to. On Windows each
/// window is matched to its process so audio can follow the picked window.
pub(crate) fn list_sources(capture_full_screen: bool) -> Vec<CaptureSource> {
    let source_type = if capture_full_screen {
        DesktopCaptureSourceType::Screen
    } else {
        DesktopCaptureSourceType::Window
    };
    let Some(capturer) = DesktopCapturer::new(DesktopCapturerOptions::new(source_type)) else {
        log::warn!("capture: could not create a desktop capturer to list sources");
        return Vec::new();
    };
    let sources = capturer.get_source_list();
    log::info!("capture: {} sources", sources.len());

    let pid_by_title = if capture_full_screen {
        Vec::new()
    } else {
        audio::window_pids()
    };
    sources
        .iter()
        .enumerate()
        .map(|(index, source)| {
            let title = source.title();
            let audio_source_pid = pid_by_title
                .iter()
                .find(|(t, _)| *t == title)
                .map(|(_, pid)| *pid);
            CaptureSource {
                index: index as u32,
                title,
                audio_source_pid,
            }
        })
        .collect()
}
