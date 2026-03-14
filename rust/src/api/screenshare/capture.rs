/// Video capture thread management
use super::types::CaptureCommand;
use super::types::CaptureSource;
use livekit::webrtc::desktop_capturer::{
    CaptureError, DesktopCaptureSourceType, DesktopCapturer, DesktopCapturerOptions, DesktopFrame,
};
use livekit::webrtc::native::yuv_helper;
use livekit::webrtc::prelude::{
    I420Buffer, VideoBuffer, VideoFrame, VideoResolution, VideoRotation,
};
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

#[cfg(target_os = "windows")]
use std::collections::HashMap;

struct SendableFrame(DesktopFrame);
unsafe impl Send for SendableFrame {}

/// RAII guard that raises the Windows timer resolution to 1 ms on creation
/// and restores it on drop. This prevents `recv_timeout` from sleeping in
/// ~15.6 ms increments on machines without other timer-requesting apps.
#[cfg(target_os = "windows")]
struct WindowsTimerResolutionGuard;

#[cfg(target_os = "windows")]
impl WindowsTimerResolutionGuard {
    fn new() -> Self {
        unsafe { windows::Win32::Media::timeBeginPeriod(1) };
        Self
    }
}

#[cfg(target_os = "windows")]
impl Drop for WindowsTimerResolutionGuard {
    fn drop(&mut self) {
        unsafe { windows::Win32::Media::timeEndPeriod(1) };
    }
}

/// Spawn the video capture thread.
/// Returns a command sender and the thread handle.
#[flutter_rust_bridge::frb(ignore)]
pub fn spawn_capture_thread(
    capture_cursor: bool,
    source_type: DesktopCaptureSourceType,
    selected_source_index: Option<u32>,
    fps: i32,
    resolution: i32,
    resolution_signal: Arc<(Mutex<Option<VideoResolution>>, Condvar)>,
    video_source_slot: Arc<Mutex<Option<NativeVideoSource>>>,
) -> (Sender<CaptureCommand>, thread::JoinHandle<()>) {
    let (command_tx, command_rx) = mpsc::channel();
    let handle = thread::spawn(move || {
        run_capture_loop(
            capture_cursor,
            source_type,
            selected_source_index,
            fps,
            resolution,
            resolution_signal,
            video_source_slot,
            command_rx,
        )
    });
    (command_tx, handle)
}

fn run_capture_loop(
    capture_cursor: bool,
    source_type: DesktopCaptureSourceType,
    selected_source_index: Option<u32>,
    fps: i32,
    resolution: i32,
    resolution_signal: Arc<(Mutex<Option<VideoResolution>>, Condvar)>,
    video_source_slot: Arc<Mutex<Option<NativeVideoSource>>>,
    command_rx: mpsc::Receiver<CaptureCommand>,
) {
    // Calculate precise frame interval from FPS
    let frame_interval = Duration::from_secs_f64(1.0 / fps as f64);
    println!("Capture FPS: {}, Frame interval: {:?}", fps, frame_interval);

    // On Windows, raise the system timer resolution to 1 ms so recv_timeout
    // wakes up on time at high frame rates instead of sleeping ~15.6 ms.
    #[cfg(target_os = "windows")]
    let _timer_guard = WindowsTimerResolutionGuard::new();

    // Create a channel for offloading raw frames to a processing worker thread
    let (frame_tx, frame_rx) = mpsc::sync_channel::<SendableFrame>(2);

    let video_source_clone = Arc::clone(&video_source_slot);
    let resolution_signal_clone = Arc::clone(&resolution_signal);

    // Spawn the dedicated processing thread for color conversion and scaling
    thread::spawn(move || {
        // Native-resolution I420 buffer (reused each frame)
        let mut native_buffer = VideoFrame {
            rotation: VideoRotation::VideoRotation0,
            buffer: I420Buffer::new(1, 1),
            timestamp_us: 0,
        };
        // Target dimensions computed once after first frame (stored as Option)
        let mut target_dims: Option<(u32, u32)> = None;
        // Cache the NativeVideoSource after it is first observed as Some.
        // video_source_slot is set once at session start and never changed, so
        // we only need to lock the mutex until we have a value — then we hold
        // the clone directly and skip the lock on every subsequent frame.
        let mut cached_source: Option<NativeVideoSource> = None;

        while let Ok(SendableFrame(frame)) = frame_rx.recv() {
            let width = frame.width();
            let height = frame.height();
            let stride = frame.stride();
            let data = frame.data();

            // Signal resolution on first frame and compute target dims
            {
                let (lock, cvar) = &*resolution_signal_clone;
                let mut guard = lock.lock().unwrap();
                if guard.is_none() {
                    *guard = Some(VideoResolution {
                        width: width as u32,
                        height: height as u32,
                    });
                    cvar.notify_all();

                    // Compute target dimensions once
                    let target_h = (resolution as u32).min(height as u32);
                    let mut target_w =
                        (target_h as f32 * width as f32 / height as f32).round() as u32;
                    if target_w % 2 != 0 {
                        target_w += 1;
                    }
                    let target_h = if target_h % 2 != 0 {
                        target_h + 1
                    } else {
                        target_h
                    };
                    target_dims = Some((target_w, target_h));
                    println!(
                        "Processing thread: scaling {}x{} → {}x{}",
                        width, height, target_w, target_h
                    );
                }
            }

            // Resize native buffer if needed
            let buffer_width = native_buffer.buffer.width() as i32;
            let buffer_height = native_buffer.buffer.height() as i32;
            if buffer_width != width || buffer_height != height {
                native_buffer.buffer = I420Buffer::new(width as u32, height as u32);
            }

            // Convert ARGB → I420 at native resolution
            let (stride_y, stride_u, stride_v) = native_buffer.buffer.strides();
            let (y_plane, u_plane, v_plane) = native_buffer.buffer.data_mut();
            yuv_helper::argb_to_i420(
                data, stride, y_plane, stride_y, u_plane, stride_u, v_plane, stride_v, width,
                height,
            );

            // Populate the source cache on the first frame (or if the slot was
            // not yet set when the previous frame arrived).
            if cached_source.is_none() {
                cached_source = video_source_clone.lock().unwrap().clone();
            }

            // Send frame to LiveKit, scaling down only when necessary.
            //
            // I420Buffer::scale() always allocates a new buffer (~3 MB at 1080p).
            // libwebrtc-0.3.26 does not expose a scale_to(&mut dst) variant, so the
            // allocation cannot be avoided when actual downscaling is needed.
            // For the common case where the screen's native resolution already matches
            // the target (e.g. 1080p screen → 1080p output) we skip scale() entirely
            // and send native_buffer directly, eliminating the per-frame allocation.
            if let (Some((target_w, target_h)), Some(source)) = (target_dims, &cached_source) {
                let needs_scale = target_w != native_buffer.buffer.width()
                    || target_h != native_buffer.buffer.height();

                if needs_scale {
                    let scaled = VideoFrame {
                        rotation: VideoRotation::VideoRotation0,
                        buffer: native_buffer.buffer.scale(target_w as i32, target_h as i32),
                        timestamp_us: 0,
                    };
                    source.capture_frame(&scaled);
                } else {
                    // Native resolution matches target — send directly, zero allocation.
                    source.capture_frame(&native_buffer);
                }
            }
        }
    });

    let callback = move |result: Result<DesktopFrame, CaptureError>| {
        if let Ok(frame) = result {
            // Wrap the frame to bypass the !Send restriction
            let _ = frame_tx.try_send(SendableFrame(frame));
        }
    };

    let mut options = DesktopCapturerOptions::new(source_type);
    options.set_include_cursor(capture_cursor);

    let mut capturer = match DesktopCapturer::new(options) {
        Some(c) => c,
        None => {
            println!("✗ Failed to create desktop capturer");
            return;
        }
    };

    let sources = capturer.get_source_list();
    println!("\n=== Available capture sources ===");
    for (i, source) in sources.iter().enumerate() {
        println!("  {}: {}", i, source.title());
    }

    let selected_idx = selected_source_index
        .map(|value| value as usize)
        .filter(|value| *value < sources.len())
        .unwrap_or(0);
    let selected_source = sources.get(selected_idx).cloned();
    if selected_source.is_none() {
        println!("✗ No capture sources available");
        return;
    }

    println!(
        "✓ Selected source [{}]: {}",
        selected_idx,
        selected_source.as_ref().unwrap().title()
    );
    println!("==================================\n");

    capturer.start_capture(selected_source, callback);

    // Initialize the target time for the very first frame
    let mut next_frame_time = Instant::now() + frame_interval;

    // Capture loop
    loop {
        // Calculate exactly how much time is left until the next frame is due.
        let timeout = next_frame_time.saturating_duration_since(Instant::now());

        match command_rx.recv_timeout(timeout) {
            Ok(CaptureCommand::Terminate) => {
                println!("Capture thread received terminate command");
                break;
            }
            Err(RecvTimeoutError::Timeout) => {
                capturer.capture_frame();

                // Advance the deadline for the next frame
                next_frame_time += frame_interval;

                // If severely lagging, reset the timer to prevent a rapid burst of queued captures
                if Instant::now() > next_frame_time {
                    next_frame_time = Instant::now() + frame_interval;
                }
            }
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }

    println!("Capture loop exiting");
}

/// List available capture sources for the requested source type.
pub fn list_capture_sources(capture_full_screen: bool) -> Vec<CaptureSource> {
    let source_type = if capture_full_screen {
        DesktopCaptureSourceType::Screen
    } else {
        DesktopCaptureSourceType::Window
    };

    let options = DesktopCapturerOptions::new(source_type);
    let capturer = match DesktopCapturer::new(options) {
        Some(c) => c,
        None => return Vec::new(),
    };

    let sources = capturer.get_source_list();
    println!(
        "Enumerated {} {} capture sources",
        sources.len(),
        if capture_full_screen {
            "screen"
        } else {
            "window"
        }
    );

    #[cfg(target_os = "windows")]
    let window_pid_map: HashMap<String, u32> = if capture_full_screen {
        HashMap::new()
    } else {
        super::audio_windows::list_audio_sources_windows()
            .into_iter()
            .map(|source| (source.title, source.pid))
            .collect()
    };

    sources
        .iter()
        .enumerate()
        .map(|(index, source)| {
            let title = source.title();

            #[cfg(target_os = "windows")]
            let audio_source_pid = if capture_full_screen {
                None
            } else {
                window_pid_map.get(&title).copied()
            };

            #[cfg(not(target_os = "windows"))]
            let audio_source_pid = None;

            println!(
                "  [{}] title=\"{}\" pid={:?}",
                index, title, audio_source_pid
            );

            CaptureSource {
                index: index as u32,
                title,
                audio_source_pid,
            }
        })
        .collect()
}
