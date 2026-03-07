/// Screenshare API for LiveKit integration
///
/// This module handles screen sharing functionality by receiving
/// configuration from Flutter and managing the LiveKit session.

use livekit::options::{TrackPublishOptions, VideoCodec};
use livekit::prelude::*;
use livekit::track::{LocalTrack, LocalVideoTrack, TrackSource};
use livekit::webrtc::desktop_capturer::{
    CaptureError, DesktopCaptureSourceType, DesktopCapturer, DesktopCapturerOptions,
    DesktopFrame,
};
use livekit::webrtc::native::yuv_helper;
use livekit::webrtc::prelude::{I420Buffer, RtcVideoSource, VideoBuffer, VideoFrame, VideoResolution, VideoRotation};
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::Duration;

pub struct ScreenShareConfig {
    pub livekit_url: String,
    pub livekit_token: String,
    pub channel_id: String,
    pub identity: String,
    pub display_name: String,
    pub resolution: i32,
    pub fps: i32,
    pub bitrate: i32,
    pub share_audio: bool,
}

enum CaptureCommand {
    Terminate,
}

// Global state to hold the room connection and capture thread
struct ScreenShareSession {
    room: Room,
    capture_tx: Sender<CaptureCommand>,
    capture_handle: thread::JoinHandle<()>,
}

static SESSION: Mutex<Option<ScreenShareSession>> = Mutex::new(None);

/// Start screen sharing with the given configuration.
/// Connects to LiveKit room with the provided token.
pub async fn start_screenshare(config: ScreenShareConfig) -> Result<String, String> {
    println!("=== SCREENSHARE DATA RECEIVED IN RUST ===");
    println!("LiveKit URL: {}", config.livekit_url);
    println!("LiveKit Token: {}", config.livekit_token);
    println!("Channel ID: {}", config.channel_id);
    println!("Identity: {}", config.identity);
    println!("Display Name: {}", config.display_name);
    println!("Resolution: {}p", config.resolution);
    println!("FPS: {}", config.fps);
    println!("Bitrate: {} Mbps", config.bitrate);
    println!("Share Audio: {}", config.share_audio);
    println!("=========================================");

    // Check if already connected
    {
        let session_lock = SESSION.lock().unwrap();
        if session_lock.is_some() {
            return Err("Already sharing screen".to_string());
        }
    }

    println!("Attempting to connect to LiveKit room...");

    // Connect to LiveKit room
    let (room, _rx) = Room::connect(&config.livekit_url, &config.livekit_token, RoomOptions::default())
        .await
        .map_err(|e| format!("Failed to connect to LiveKit: {:?}", e))?;

    let room_name = room.name().to_string();
    let room_sid = room.sid().await.to_string();

    println!("✓ Successfully connected to LiveKit room!");
    println!("  Room name: {}", room_name);
    println!("  Room SID: {}", room_sid);
    println!("  Identity: {}", config.identity);

    // Set up capture synchronization primitives
    let resolution_signal: Arc<(Mutex<Option<VideoResolution>>, Condvar)> =
        Arc::new((Mutex::new(None), Condvar::new()));
    let video_source_slot: Arc<Mutex<Option<NativeVideoSource>>> = Arc::new(Mutex::new(None));

    // Spawn video capture thread
    println!("Starting video capture thread...");
    let (capture_tx, capture_handle) = spawn_capture_thread(
        true, // capture_cursor
        DesktopCaptureSourceType::Screen,
        resolution_signal.clone(),
        video_source_slot.clone(),
    );

    // Wait for capture resolution
    println!("Waiting for capture resolution...");
    let resolution = wait_for_resolution(&resolution_signal);
    println!("✓ Detected capture resolution: {}x{}", resolution.width, resolution.height);

    // Publish video track
    println!("Publishing video track...");
    let buffer_source = publish_video_track(&room, resolution).await
        .map_err(|e| format!("Failed to publish video track: {:?}", e))?;

    {
        let mut slot = video_source_slot.lock().unwrap();
        *slot = Some(buffer_source);
    }

    println!("✓ Screen sharing started successfully!");

    // Store the session
    {
        let mut session_lock = SESSION.lock().unwrap();
        *session_lock = Some(ScreenShareSession {
            room,
            capture_tx,
            capture_handle,
        });
    }

    Ok(format!("Connected to room: {} ({})", room_name, room_sid))
}

/// Wait for the capture thread to detect the resolution
fn wait_for_resolution(signal: &Arc<(Mutex<Option<VideoResolution>>, Condvar)>) -> VideoResolution {
    let (lock, cvar) = &**signal;
    let mut guard = lock.lock().unwrap();
    while guard.is_none() {
        guard = cvar.wait(guard).unwrap();
    }
    guard.clone().unwrap()
}

/// Publish a video track for screen sharing
async fn publish_video_track(
    room: &Room,
    resolution: VideoResolution,
) -> Result<NativeVideoSource, String> {
    let buffer_source = NativeVideoSource::new(resolution, true);

    let track = LocalVideoTrack::create_video_track(
        "screen_share",
        RtcVideoSource::Native(buffer_source.clone()),
    );

    room.local_participant()
        .publish_track(
            LocalTrack::Video(track),
            TrackPublishOptions {
                source: TrackSource::Screenshare,
                video_codec: VideoCodec::VP9,
                ..Default::default()
            },
        )
        .await
        .map_err(|e| format!("Failed to publish track: {:?}", e))?;

    Ok(buffer_source)
}

/// Spawn the video capture thread
fn spawn_capture_thread(
    capture_cursor: bool,
    source_type: DesktopCaptureSourceType,
    resolution_signal: Arc<(Mutex<Option<VideoResolution>>, Condvar)>,
    video_source_slot: Arc<Mutex<Option<NativeVideoSource>>>,
) -> (Sender<CaptureCommand>, thread::JoinHandle<()>) {
    let (command_tx, command_rx) = mpsc::channel();
    let handle = thread::spawn(move || {
        run_capture_loop(
            capture_cursor,
            source_type,
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
    resolution_signal: Arc<(Mutex<Option<VideoResolution>>, Condvar)>,
    video_source_slot: Arc<Mutex<Option<NativeVideoSource>>>,
    command_rx: mpsc::Receiver<CaptureCommand>,
) {
    let callback = {
        let mut frame_buffer = VideoFrame {
            rotation: VideoRotation::VideoRotation0,
            buffer: I420Buffer::new(1, 1),
            timestamp_us: 0,
        };
        move |result: Result<DesktopFrame, CaptureError>| {
            let frame = match result {
                Ok(frame) => frame,
                Err(CaptureError::Temporary) => return,
                Err(CaptureError::Permanent) => return,
            };

            let width = frame.width();
            let height = frame.height();
            let stride = frame.stride();
            let data = frame.data();

            // Signal resolution on first frame
            {
                let (lock, cvar) = &*resolution_signal;
                let mut guard = lock.lock().unwrap();
                if guard.is_none() {
                    *guard = Some(VideoResolution {
                        width: width as u32,
                        height: height as u32,
                    });
                    cvar.notify_all();
                }
            }

            // Resize buffer if needed
            let buffer_width = frame_buffer.buffer.width() as i32;
            let buffer_height = frame_buffer.buffer.height() as i32;
            if buffer_width != width || buffer_height != height {
                frame_buffer.buffer = I420Buffer::new(width as u32, height as u32);
            }

            // Convert ARGB to I420
            let (stride_y, stride_u, stride_v) = frame_buffer.buffer.strides();
            let (y_plane, u_plane, v_plane) = frame_buffer.buffer.data_mut();
            yuv_helper::argb_to_i420(
                data, stride, y_plane, stride_y, u_plane, stride_u, v_plane, stride_v, width,
                height,
            );

            // Send frame to LiveKit
            let slot = video_source_slot.lock().unwrap();
            if let Some(source) = slot.as_ref() {
                source.capture_frame(&frame_buffer);
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
        match command_rx.recv_timeout(Duration::from_millis(16)) {
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

/// Stop screen sharing and disconnect from LiveKit.
pub async fn stop_screenshare() -> Result<String, String> {
    println!("=== STOPPING SCREENSHARE IN RUST ===");

    // Extract the session from the Mutex
    let session_option = {
        let mut session_lock = SESSION.lock().unwrap();
        session_lock.take()
    };

    if let Some(session) = session_option {
        println!("Stopping capture thread...");

        // Send terminate command to capture thread
        let _ = session.capture_tx.send(CaptureCommand::Terminate);

        // Wait for capture thread to finish
        if let Err(e) = session.capture_handle.join() {
            println!("⚠ Warning: Capture thread join error: {:?}", e);
        }

        println!("Disconnecting from LiveKit room...");

        // Close the room connection
        if let Err(e) = session.room.close().await {
            println!("⚠ Warning during disconnect: {:?}", e);
        }

        println!("✓ Successfully stopped screen sharing");
        Ok("Stopped successfully".to_string())
    } else {
        println!("No active screen sharing session");
        Ok("No active session".to_string())
    }
}
