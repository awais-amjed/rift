/// Screenshare API for LiveKit integration
///
/// This module handles screen sharing functionality by receiving
/// configuration from Flutter and managing the LiveKit session.

pub mod capture;
pub mod track;
pub mod types;

pub use types::ScreenShareConfig;

use capture::spawn_capture_thread;
use track::publish_video_track;
use types::{CaptureCommand, ScreenShareSession, SESSION};

use livekit::prelude::*;
use livekit::webrtc::desktop_capturer::DesktopCaptureSourceType;
use livekit::webrtc::prelude::VideoResolution;
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::sync::{Arc, Condvar, Mutex};

/// Start screen sharing with the given configuration.
/// Connects to LiveKit room with the provided token.
pub async fn start_screenshare(config: ScreenShareConfig) -> Result<String, String> {
    println!("=== SCREENSHARE DATA RECEIVED IN RUST ===");
    println!("LiveKit URL: {}", config.livekit_url);
    println!("LiveKit Token: {}", config.livekit_token);
    println!("Channel ID: {}", config.channel_id);
    println!("Identity: {}", config.identity);
    println!("Display Name: {}", config.display_name);
    println!("Resolution Target: {}p", config.resolution);
    println!("FPS: {}", config.fps);
    println!("Bitrate: {} Mbps", config.bitrate);
    println!("Share Audio: {}", config.share_audio);
    println!(
        "Capture Type: {}",
        if config.capture_full_screen { "Full Screen" } else { "Window" }
    );
    println!("=========================================");

    {
        let session_lock = SESSION.lock().unwrap();
        if session_lock.is_some() {
            return Err("Already sharing screen".to_string());
        }
    }

    println!("Attempting to connect to LiveKit room...");

    let (room, _rx) =
        Room::connect(&config.livekit_url, &config.livekit_token, RoomOptions::default())
            .await
            .map_err(|e| format!("Failed to connect to LiveKit: {:?}", e))?;

    let room_name = room.name().to_string();
    let room_sid = room.sid().await.to_string();

    println!("✓ Successfully connected to LiveKit room!");
    println!("  Room name: {}", room_name);
    println!("  Room SID: {}", room_sid);
    println!("  Identity: {}", config.identity);

    let resolution_signal: Arc<(Mutex<Option<VideoResolution>>, Condvar)> =
        Arc::new((Mutex::new(None), Condvar::new()));
    let video_source_slot: Arc<Mutex<Option<NativeVideoSource>>> = Arc::new(Mutex::new(None));

    let source_type = if config.capture_full_screen {
        DesktopCaptureSourceType::Screen
    } else {
        DesktopCaptureSourceType::Window
    };

    println!("Starting video capture thread...");
    let (capture_tx, capture_handle) = spawn_capture_thread(
        true, // capture_cursor
        source_type,
        config.fps,
        config.resolution,
        resolution_signal.clone(),
        video_source_slot.clone(),
    );

    println!("Waiting for native capture resolution...");
    let native_resolution = wait_for_resolution(&resolution_signal);
    println!(
        "✓ Detected native resolution: {}x{}",
        native_resolution.width, native_resolution.height
    );

    let target_height = (config.resolution as u32).min(native_resolution.height);
    let mut target_width = (target_height as f32 * native_resolution.width as f32
        / native_resolution.height as f32)
        .round() as u32;
    if target_width % 2 != 0 { target_width += 1; }
    let target_height = if target_height % 2 != 0 { target_height + 1 } else { target_height };
    let target_resolution = VideoResolution { width: target_width, height: target_height };
    println!("✓ Target resolution: {}x{}", target_resolution.width, target_resolution.height);

    let buffer_source = NativeVideoSource::new(target_resolution.clone(), true);
    {
        let mut slot = video_source_slot.lock().unwrap();
        *slot = Some(buffer_source.clone());
    }

    println!("Publishing video track...");
    publish_video_track(&room, buffer_source, &config)
        .await
        .map_err(|e| format!("Failed to publish video track: {:?}", e))?;

    println!("✓ Screen sharing started successfully!");

    {
        let mut session_lock = SESSION.lock().unwrap();
        *session_lock = Some(ScreenShareSession { room, capture_tx, capture_handle });
    }

    Ok(format!("Connected to room: {} ({})", room_name, room_sid))
}

/// Stop screen sharing and disconnect from LiveKit.
pub async fn stop_screenshare() -> Result<String, String> {
    println!("=== STOPPING SCREENSHARE IN RUST ===");

    let session_option = {
        let mut session_lock = SESSION.lock().unwrap();
        session_lock.take()
    };

    if let Some(session) = session_option {
        println!("Stopping capture thread...");
        let _ = session.capture_tx.send(CaptureCommand::Terminate);

        if let Err(e) = session.capture_handle.join() {
            println!("⚠ Warning: Capture thread join error: {:?}", e);
        }

        println!("Disconnecting from LiveKit room...");
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

/// Wait for the capture thread to signal the first captured resolution.
fn wait_for_resolution(signal: &Arc<(Mutex<Option<VideoResolution>>, Condvar)>) -> VideoResolution {
    let (lock, cvar) = &**signal;
    let mut guard = lock.lock().unwrap();
    while guard.is_none() {
        guard = cvar.wait(guard).unwrap();
    }
    guard.clone().unwrap()
}


