//! Screenshare API for LiveKit integration.
//!
//! Receives configuration from Flutter and manages the LiveKit session.
//!
//! Every function Dart can call exists on every platform, because the bridge
//! is generated once and its bindings are not conditional. What varies is
//! whether there is anything behind them: capturing a desktop needs
//! libwebrtc's `desktop_capturer`, which exists only on the three targets
//! below, so a phone gets the same API answering "there is no desktop here"
//! and shares its screen through the Dart SDK instead.
pub mod audio_linux;
pub mod audio_windows;
pub mod capture;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub mod track;
pub mod types;

pub use audio_linux::{list_audio_sources, AudioSource};
pub use audio_windows::{list_audio_sources_windows, AudioSourceWindows};
pub use types::CaptureSource;
pub use types::ScreenShareConfig;

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use capture::{list_capture_sources as list_capture_sources_impl, spawn_capture_thread};
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use track::publish_video_track;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use types::{CaptureCommand, ScreenShareSession, SESSION};

use crate::frb_generated::StreamSink;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use livekit::e2ee::key_provider::{KeyProvider, KeyProviderOptions};
use livekit::e2ee::{E2eeOptions, EncryptionType};
use livekit::prelude::*;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use livekit::webrtc::desktop_capturer::DesktopCaptureSourceType;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use livekit::webrtc::prelude::VideoResolution;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use livekit::webrtc::video_source::native::NativeVideoSource;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use std::sync::{Arc, Condvar};
use std::sync::Mutex;

/// Lifecycle events pushed from the Rust screenshare layer up to Flutter.
pub enum ScreenshareEvent {
    /// The captured window was closed/destroyed, so capture stopped at the
    /// source. Flutter should tear the session down and update its UI.
    SourceClosed,
}

// Sink for delivering [ScreenshareEvent]s to Dart. Set once when Flutter
// subscribes; replaced if it subscribes again.
static EVENT_SINK: Mutex<Option<StreamSink<ScreenshareEvent>>> = Mutex::new(None);

/// Subscribe to screenshare lifecycle events (e.g. the shared window closing).
/// Flutter listens to the returned stream for the app's lifetime.
pub fn screenshare_event_stream(sink: StreamSink<ScreenshareEvent>) {
    *EVENT_SINK.lock().unwrap() = Some(sink);
}

/// Emit an event to Flutter if a listener is attached. Safe to call from the
/// capture thread.
#[flutter_rust_bridge::frb(ignore)]
pub fn emit_screenshare_event(event: ScreenshareEvent) {
    if let Some(sink) = EVENT_SINK.lock().unwrap().as_ref() {
        let _ = sink.add(event);
    }
}

/// There is no desktop to capture here. Reported rather than ignored: the
/// caller is about to show a "sharing" state for a stream that will never
/// arrive, and mobile is meant to take the Dart SDK's path instead.
#[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
pub async fn start_screenshare(_config: ScreenShareConfig) -> Result<String, String> {
    Err("Screen sharing from Rust is desktop-only on this build".to_string())
}

/// Start screen sharing with the given configuration.
/// Connects to LiveKit room with the provided token.
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
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
        if config.capture_full_screen {
            "Full Screen"
        } else {
            "Window"
        }
    );
    println!(
        "Selected Source Index: {:?}",
        config.selected_video_source_index
    );
    println!("Codec: {}", config.codec);
    println!("=========================================");

    {
        let session_lock = SESSION.lock().unwrap();
        if session_lock.is_some() {
            return Err("Already sharing screen".to_string());
        }
    }

    println!("Attempting to connect to LiveKit room...");

    // Same key as the rest of the call. `with_shared_key` is right here and not
    // in the app: this connection publishes one track and subscribes to
    // nothing, so it never needs anyone else's key — and the app's
    // per-participant mode exists only so a bot can be given a different one.
    if config.e2ee_key.len() != 32 {
        return Err("Missing the channel key for this call".to_string());
    }
    let key_provider = KeyProvider::with_shared_key(
        KeyProviderOptions::default(),
        config.e2ee_key.clone(),
    );
    key_provider.set_shared_key(config.e2ee_key.clone(), config.e2ee_key_index);

    // `RoomOptions` is non-exhaustive upstream, so it is built and then set
    // rather than written as a literal.
    let mut room_options = RoomOptions::default();
    room_options.e2ee = Some(E2eeOptions {
        encryption_type: EncryptionType::Gcm,
        key_provider,
    });

    let (room, _rx) = Room::connect(
        &config.livekit_url,
        &config.livekit_token,
        room_options,
    )
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
        config.selected_video_source_index,
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
    if target_width % 2 != 0 {
        target_width += 1;
    }
    let target_height = if target_height % 2 != 0 {
        target_height + 1
    } else {
        target_height
    };
    let target_resolution = VideoResolution {
        width: target_width,
        height: target_height,
    };
    println!(
        "✓ Target resolution: {}x{}",
        target_resolution.width, target_resolution.height
    );

    let buffer_source = NativeVideoSource::new(target_resolution.clone(), false);
    {
        let mut slot = video_source_slot.lock().unwrap();
        *slot = Some(buffer_source.clone());
    }

    println!("Publishing video track...");
    publish_video_track(&room, buffer_source, &config)
        .await
        .map_err(|e| format!("Failed to publish video track: {:?}", e))?;

    // Start audio capture if requested and audio source is selected
    #[cfg(target_os = "linux")]
    let audio_handle = if config.share_audio
        && config.selected_audio_source_index.is_some()
        && config.selected_audio_source_sink.is_some()
    {
        let sink_input_idx = config.selected_audio_source_index.unwrap();
        let sink_idx = config.selected_audio_source_sink.unwrap();
        println!(
            "Starting audio capture for sink-input #{}, sink #{}...",
            sink_input_idx, sink_idx
        );
        match audio_linux::start_audio_capture(&room, sink_input_idx, sink_idx).await {
            Some(handle) => {
                println!("✓ Audio capture started successfully");
                Some(handle)
            }
            None => {
                println!("⚠ Failed to start audio capture");
                None
            }
        }
    } else {
        if config.share_audio {
            println!("Audio sharing enabled but no audio source selected");
        }
        None
    };

    #[cfg(target_os = "windows")]
    let audio_handle = if config.share_audio {
        let pid = config.selected_audio_source_pid;
        if let Some(pid_value) = pid {
            println!("Starting Windows audio capture for PID {}...", pid_value);
        } else {
            println!("Starting Windows system audio capture...");
        }

        match audio_windows::start_audio_capture(&room, pid).await {
            Some(handle) => {
                println!("✓ Windows audio capture started successfully");
                Some(handle)
            }
            None => {
                println!("⚠ Failed to start Windows audio capture");
                None
            }
        }
    } else {
        None
    };

    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    let audio_handle = None;

    println!("✓ Screen sharing started successfully!");

    {
        let mut session_lock = SESSION.lock().unwrap();
        *session_lock = Some(ScreenShareSession {
            room,
            capture_tx,
            capture_handle,
            audio_handle,
        });
    }

    Ok(format!("Connected to room: {} ({})", room_name, room_sid))
}

/// Nothing was ever started, so stopping succeeds — a teardown path that
/// errors would make every disconnect look like a failure.
#[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
pub async fn stop_screenshare() -> Result<String, String> {
    Ok("No active session".to_string())
}

/// Stop screen sharing and disconnect from LiveKit.
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub async fn stop_screenshare() -> Result<String, String> {
    println!("=== STOPPING SCREENSHARE IN RUST ===");

    let session_option = {
        let mut session_lock = SESSION.lock().unwrap();
        session_lock.take()
    };

    if let Some(session) = session_option {
        let _ = session.capture_tx.send(CaptureCommand::Terminate);

        let capture_handle = session.capture_handle;
        let audio_handle = session.audio_handle;

        // Run LiveKit room teardown and all blocking thread joins concurrently.
        // Previously these were sequential: join capture → join audio → close room.
        // The DesktopCapturer drop (inside the capture thread join) releases the WGC
        // capture session, which is what causes the shared window to appear frozen.
        // By closing the room at the same time, viewers see the stream end immediately
        // and the local window unblocks as soon as the WGC teardown finishes —
        // without also waiting for the network disconnect first.
        let (room_result, _) = tokio::join!(
            session.room.close(),
            tokio::task::spawn_blocking(move || {
                println!("Stopping capture thread...");
                let _ = capture_handle.join();

                #[cfg(target_os = "linux")]
                if let Some(h) = audio_handle {
                    println!("Stopping audio capture...");
                    h.terminate();
                }

                #[cfg(target_os = "windows")]
                if let Some(h) = audio_handle {
                    println!("Stopping Windows audio capture...");
                    h.terminate();
                }
            }),
        );

        if let Err(e) = room_result {
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
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
fn wait_for_resolution(signal: &Arc<(Mutex<Option<VideoResolution>>, Condvar)>) -> VideoResolution {
    let (lock, cvar) = &**signal;
    let mut guard = lock.lock().unwrap();
    while guard.is_none() {
        guard = cvar.wait(guard).unwrap();
    }
    guard.clone().unwrap()
}

/// List desktop capture sources for either full-screen or window sharing.
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub fn list_capture_sources(capture_full_screen: bool) -> Vec<CaptureSource> {
    list_capture_sources_impl(capture_full_screen)
}

/// Nothing to enumerate. See the module doc.
#[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
pub fn list_capture_sources(_capture_full_screen: bool) -> Vec<CaptureSource> {
    Vec::new()
}
