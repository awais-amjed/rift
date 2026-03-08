/// Video capture thread management

use super::types::CaptureCommand;
use livekit::webrtc::desktop_capturer::{
    CaptureError, DesktopCaptureSourceType, DesktopCapturer, DesktopCapturerOptions,
    DesktopFrame,
};
use livekit::webrtc::native::yuv_helper;
use livekit::webrtc::prelude::{
    I420Buffer, VideoBuffer, VideoFrame, VideoResolution, VideoRotation,
};
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::Duration;

/// Spawn the video capture thread.
/// Returns a command sender and the thread handle.
#[flutter_rust_bridge::frb(ignore)]
pub fn spawn_capture_thread(
    capture_cursor: bool,
    source_type: DesktopCaptureSourceType,
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
    fps: i32,
    resolution: i32,
    resolution_signal: Arc<(Mutex<Option<VideoResolution>>, Condvar)>,
    video_source_slot: Arc<Mutex<Option<NativeVideoSource>>>,
    command_rx: mpsc::Receiver<CaptureCommand>,
) {
    // Calculate frame interval from FPS (in milliseconds)
    let frame_interval_ms = (1000.0 / fps as f64) as u64;
    println!("Capture FPS: {}, Frame interval: {}ms", fps, frame_interval_ms);

    let callback = {
        // Native-resolution I420 buffer (reused each frame)
        let mut native_buffer = VideoFrame {
            rotation: VideoRotation::VideoRotation0,
            buffer: I420Buffer::new(1, 1),
            timestamp_us: 0,
        };
        // Target dimensions computed once after first frame (stored as Option)
        let mut target_dims: Option<(u32, u32)> = None;

        move |result: Result<DesktopFrame, CaptureError>| {
            let frame = match result {
                Ok(frame) => frame,
                Err(CaptureError::Temporary) | Err(CaptureError::Permanent) => return,
            };

            let width = frame.width();
            let height = frame.height();
            let stride = frame.stride();
            let data = frame.data();

            // Signal resolution on first frame and compute target dims
            {
                let (lock, cvar) = &*resolution_signal;
                let mut guard = lock.lock().unwrap();
                if guard.is_none() {
                    *guard = Some(VideoResolution {
                        width: width as u32,
                        height: height as u32,
                    });
                    cvar.notify_all();

                    // Compute target dimensions once
                    let target_h = (resolution as u32).min(height as u32);
                    let mut target_w = (target_h as f32 * width as f32 / height as f32).round() as u32;
                    if target_w % 2 != 0 { target_w += 1; }
                    let target_h = if target_h % 2 != 0 { target_h + 1 } else { target_h };
                    target_dims = Some((target_w, target_h));
                    println!("Capture thread: scaling {}x{} → {}x{}", width, height, target_w, target_h);
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

            // Scale down to target resolution
            let send_frame = if let Some((target_w, target_h)) = target_dims {
                VideoFrame {
                    rotation: VideoRotation::VideoRotation0,
                    buffer: native_buffer.buffer.scale(target_w as i32, target_h as i32),
                    timestamp_us: 0,
                }
            } else {
                return; // target dims not yet computed, skip frame
            };

            // Send scaled frame to LiveKit
            let slot = video_source_slot.lock().unwrap();
            if let Some(source) = slot.as_ref() {
                source.capture_frame(&send_frame);
            }
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

    // Auto-select first screen (index 0)
    let selected_source = sources.get(0).cloned();
    if selected_source.is_none() {
        println!("✗ No capture sources available");
        return;
    }

    println!("✓ Auto-selected: {}", selected_source.as_ref().unwrap().title());
    println!("==================================\n");

    capturer.start_capture(selected_source, callback);

    // Capture loop
    loop {
        match command_rx.recv_timeout(Duration::from_millis(frame_interval_ms)) {
            Ok(CaptureCommand::Terminate) => {
                println!("Capture thread received terminate command");
                break;
            }
            Err(RecvTimeoutError::Timeout) => {
                capturer.capture_frame();
            }
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }

    println!("Capture loop exiting");
}

