//! One screen share at a time: bringing it up, and taking it down again.
use super::audio::{self, AudioCaptureHandle};
use super::capture::{self, Capture, CaptureRequest};
use super::resolution::target_size;
use super::track::publish_video_track;
use crate::api::screenshare::types::{self, ScreenShareConfig};
use livekit::e2ee::key_provider::{KeyProvider, KeyProviderOptions};
use livekit::e2ee::{E2eeOptions, EncryptionType};
use livekit::prelude::*;
use livekit::webrtc::desktop_capturer::DesktopCaptureSourceType;
use livekit::webrtc::prelude::VideoResolution;
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::time::Duration;
use tokio::sync::Mutex;

/// How long the selected source gets to deliver its first frame. A minimised
/// window, or a Wayland portal the user dismissed, never delivers one.
const FIRST_FRAME_TIMEOUT: Duration = Duration::from_secs(10);

struct Session {
    room: Room,
    capture: Capture,
    audio: Option<AudioCaptureHandle>,
}

// An async mutex, held for the whole of a start or a stop. A second start
// waits for the first to finish and then finds it "already sharing"; a stop
// during a start waits for the start and then stops it, rather than finding
// nothing and leaving a room connected that no one can reach any more.
static SESSION: Mutex<Option<Session>> = Mutex::const_new(None);

pub(crate) async fn start(config: ScreenShareConfig) -> Result<String, String> {
    types::check(&config)?;
    let mut slot = SESSION.lock().await;
    if slot.is_some() {
        return Err("Already sharing screen".to_string());
    }
    log::info!(
        "screenshare: starting {}p{} at {} Mbps, {:?}, {}, audio {}",
        config.resolution,
        config.fps,
        config.bitrate,
        config.codec,
        if config.capture_full_screen {
            "screen"
        } else {
            "window"
        },
        config.share_audio,
    );

    let room = connect(&config).await?;
    let room_name = room.name().to_string();
    let room_sid = room.sid().await.to_string();
    log::info!("screenshare: connected to room {room_name} ({room_sid})");

    let (capture, audio) = match bring_up(&room, &config).await {
        Ok(parts) => parts,
        Err(reason) => {
            // Leave nothing behind: a room left open here is a ghost
            // participant the app has no handle to.
            if let Err(e) = room.close().await {
                log::warn!("screenshare: closing after a failed start: {e:?}");
            }
            return Err(reason);
        }
    };

    // Point every cryptor at the slot the room is actually reading.
    //
    // The Rust SDK creates a sender's frame cryptor and never sets its key
    // index, so it encrypts into libwebrtc's default slot 0 — while every Rift
    // client looks this identity up at `keyVersion % 16`. The share then
    // publishes happily and decrypts for nobody: the sharer sees "sharing", the
    // room sees a black tile, and nothing anywhere reports an error.
    //
    // After both tracks, because a cryptor does not exist until its track does,
    // and the system-audio track is published later than the video one.
    for (_, cryptor) in room.e2ee_manager().frame_cryptors() {
        cryptor.set_key_index(config.e2ee_key_index);
    }

    *slot = Some(Session {
        room,
        capture,
        audio,
    });
    log::info!("screenshare: started");
    Ok(format!("Connected to room: {room_name} ({room_sid})"))
}

pub(crate) async fn stop() -> Result<String, String> {
    let mut slot = SESSION.lock().await;
    let Some(Session {
        room,
        capture,
        audio,
    }) = slot.take()
    else {
        log::info!("screenshare: stop with nothing running");
        return Ok("No active session".to_string());
    };

    // Room teardown and the blocking thread joins run at the same time. The
    // capturer's drop (inside the capture join) releases the WGC session,
    // which is what unfreezes the shared window on Windows; closing the room
    // concurrently means viewers see the stream end without also waiting for
    // that, and the window unblocks without waiting for the network.
    let (room_result, _) = tokio::join!(
        room.close(),
        tokio::task::spawn_blocking(move || {
            capture.stop();
            if let Some(audio) = audio {
                audio.terminate();
            }
        }),
    );
    if let Err(e) = room_result {
        log::warn!("screenshare: disconnect reported {e:?}");
    }
    log::info!("screenshare: stopped");
    Ok("Stopped successfully".to_string())
}

async fn connect(config: &ScreenShareConfig) -> Result<Room, String> {
    // Same key as the rest of the call. `with_shared_key` is right here and not
    // in the app: this connection publishes one track and subscribes to
    // nothing, so it never needs anyone else's key — and the app's
    // per-participant mode exists only so a bot can be given a different one.
    let key_provider =
        KeyProvider::with_shared_key(KeyProviderOptions::default(), config.e2ee_key.clone());
    key_provider.set_shared_key(config.e2ee_key.clone(), config.e2ee_key_index);

    // `RoomOptions` is non-exhaustive upstream, so it is built and then set
    // rather than written as a literal.
    let mut room_options = RoomOptions::default();
    room_options.encryption = Some(E2eeOptions {
        encryption_type: EncryptionType::Gcm,
        key_provider,
    });

    let (room, _events) = Room::connect(&config.livekit_url, &config.livekit_token, room_options)
        .await
        .map_err(|e| format!("Failed to connect to LiveKit: {e:?}"))?;
    Ok(room)
}

/// Everything after the room exists. On any error the capture thread is
/// already stopped; the caller closes the room.
async fn bring_up(
    room: &Room,
    config: &ScreenShareConfig,
) -> Result<(Capture, Option<AudioCaptureHandle>), String> {
    let (capture, first_frame) = capture::spawn(CaptureRequest {
        source_type: if config.capture_full_screen {
            DesktopCaptureSourceType::Screen
        } else {
            DesktopCaptureSourceType::Window
        },
        selected_index: config.selected_video_source_index,
        fps: config.fps,
        max_height: config.resolution,
        capture_cursor: true,
    });

    let native = match tokio::time::timeout(FIRST_FRAME_TIMEOUT, first_frame).await {
        Ok(Ok(Ok(size))) => size,
        Ok(Ok(Err(reason))) => return Err(stop_capture(capture, reason).await),
        Ok(Err(_)) => {
            let reason = "The capture thread stopped before producing a frame".to_string();
            return Err(stop_capture(capture, reason).await);
        }
        Err(_) => {
            let reason = format!(
                "No frames arrived from the selected source in {} seconds; is it minimised?",
                FIRST_FRAME_TIMEOUT.as_secs()
            );
            return Err(stop_capture(capture, reason).await);
        }
    };

    let target = target_size(native, config.resolution);
    log::info!(
        "screenshare: capturing {}x{}, publishing {}x{}",
        native.width,
        native.height,
        target.width,
        target.height
    );
    let source = NativeVideoSource::new(
        VideoResolution {
            width: target.width,
            height: target.height,
        },
        false,
    );
    capture.attach(source.clone());

    if let Err(reason) = publish_video_track(room, source, config).await {
        return Err(stop_capture(capture, reason).await);
    }

    let audio = if config.share_audio {
        audio::start(room, config).await
    } else {
        None
    };
    Ok((capture, audio))
}

/// Stop a capture off the async runtime, and hand back the reason it is being
/// stopped so the error path reads as one expression.
async fn stop_capture(capture: Capture, reason: String) -> String {
    let _ = tokio::task::spawn_blocking(move || capture.stop()).await;
    reason
}
