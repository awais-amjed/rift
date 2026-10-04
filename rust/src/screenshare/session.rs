//! One screen share at a time: bringing it up, and taking it down again.
use super::capture::{self, Capture, CaptureRequest, Progress, Started, VideoSlot};
use super::resolution::{target_size, Size};
use super::track::{publish_video_track, TrackSettings};
use crate::api::screenshare::types::{self, ScreenShareConfig};
use crate::sharing::audio::{self, AudioCapture, AudioCaptureHandle, AudioSelection};
use crate::sharing::room;
use livekit::prelude::*;
use livekit::webrtc::desktop_capturer::DesktopCaptureSourceType;
use livekit::webrtc::prelude::VideoResolution;
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::collections::HashMap;
use std::time::Duration;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

/// How long the selected source gets to deliver its first frame, or to say
/// it is waiting for a minimised window. A Wayland portal the user dismissed
/// never does either.
const FIRST_FRAME_TIMEOUT: Duration = Duration::from_secs(10);

/// The participant attribute a share sets while its window is minimised, which
/// viewers read to say the picture is paused (`VoiceAttributes.sharePausedKey`).
const PAUSED_ATTRIBUTE: &str = "paused";

struct Session {
    room: Room,
    capture: Capture,
    audio: Option<AudioCaptureHandle>,
    /// Publishes the picture when its first frame arrives, for a share that
    /// started on a minimised window and is waiting for it to be opened.
    publisher: Option<JoinHandle<()>>,
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

    let room = room::connect(
        &config.livekit_url,
        &config.livekit_token,
        &config.e2ee_key,
        config.e2ee_key_index,
    )
    .await?;
    let room_name = room.name().to_string();
    let room_sid = room.sid().await.to_string();
    log::info!("screenshare: connected to room {room_name} ({room_sid})");

    let (capture, audio, publisher) = match bring_up(&room, &config).await {
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

    *slot = Some(Session {
        room,
        capture,
        audio,
        publisher,
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
        publisher,
    }) = slot.take()
    else {
        log::info!("screenshare: stop with nothing running");
        return Ok("No active session".to_string());
    };
    if let Some(publisher) = publisher {
        publisher.abort();
    }

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

/// Everything after the room exists. On any error the capture thread is
/// already stopped; the caller closes the room.
async fn bring_up(
    room: &Room,
    config: &ScreenShareConfig,
) -> Result<(Capture, Option<AudioCaptureHandle>, Option<JoinHandle<()>>), String> {
    let (capture, mut started) = capture::spawn(CaptureRequest {
        source_type: if config.capture_full_screen {
            DesktopCaptureSourceType::Screen
        } else {
            DesktopCaptureSourceType::Window
        },
        selected_index: config.selected_video_source_index,
        fps: config.fps,
        max_height: config.resolution,
        capture_cursor: true,
        on_minimised: Some(announce_paused(room)),
    });

    let first = match tokio::time::timeout(FIRST_FRAME_TIMEOUT, started.recv()).await {
        Ok(Some(Progress::FirstFrame(size))) => Some(size),
        Ok(Some(Progress::Waiting)) => None,
        Ok(Some(Progress::Failed(reason))) => return Err(stop_capture(capture, reason).await),
        Ok(None) => {
            let reason = "The capture thread stopped before producing a frame".to_string();
            return Err(stop_capture(capture, reason).await);
        }
        Err(_) => {
            let reason = format!(
                "No frames arrived from the selected source in {} seconds",
                FIRST_FRAME_TIMEOUT.as_secs()
            );
            return Err(stop_capture(capture, reason).await);
        }
    };

    let video = Video {
        participant: room.local_participant(),
        slot: capture.slot(),
        settings: TrackSettings::from(config),
    };
    // A window still on the taskbar: the share is up — viewers see it, marked
    // paused — and the picture goes out once the user opens the window, which
    // is theirs to do when they are ready. Waiting here instead would hold the
    // session lock, and with it any stop, for as long as that takes.
    let publisher = match first {
        Some(native) => {
            if let Err(reason) = video.publish(native).await {
                return Err(stop_capture(capture, reason).await);
            }
            None
        }
        None => {
            log::info!("screenshare: waiting for the window to be opened");
            Some(tokio::spawn(publish_when_opened(video, started)))
        }
    };

    // A screen share's sound has no `on_ended`: if the window stops playing,
    // the picture is still worth watching. Its track keeps the plain name it
    // has always had — nothing reads it, because the picture says what this is.
    let audio = if config.share_audio {
        audio::start(
            room,
            AudioCapture {
                selection: AudioSelection::from(config),
                track_name: "screen_share_audio".to_string(),
                on_ended: None,
            },
        )
        .await
    } else {
        None
    };
    Ok((capture, audio, publisher))
}

/// What publishing the picture needs, none of it borrowed from the start.
struct Video {
    participant: LocalParticipant,
    slot: VideoSlot,
    settings: TrackSettings,
}

impl Video {
    /// Size a video source for the first frame, start feeding it, publish it.
    async fn publish(&self, native: Size) -> Result<(), String> {
        let target = target_size(native, self.settings.max_height);
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
        self.slot.attach(source.clone());
        publish_video_track(&self.participant, source, &self.settings).await
    }
}

/// The rest of a share that started on a minimised window. A stop aborts it;
/// a window closed while waiting has already told Flutter, which stops it.
async fn publish_when_opened(video: Video, mut started: Started) {
    while let Some(progress) = started.recv().await {
        match progress {
            Progress::Waiting => {}
            Progress::Failed(reason) => {
                log::info!("screenshare: gave up waiting: {reason}");
                return;
            }
            Progress::FirstFrame(native) => {
                if let Err(reason) = video.publish(native).await {
                    // The share is up with nothing to show and no way to put
                    // it right from here: end it, the way a closed window does.
                    log::warn!("screenshare: {reason}");
                    crate::api::screenshare::emit_screenshare_event(
                        crate::api::screenshare::types::ScreenshareEvent::SourceClosed,
                    );
                }
                return;
            }
        }
    }
}

/// Tells the room, as an attribute of the share's own connection, when the
/// shared window is minimised and when it is back. Called from the capture
/// thread, so the request is handed to the runtime rather than awaited there.
fn announce_paused(room: &Room) -> Box<dyn Fn(bool) + Send> {
    let participant = room.local_participant();
    let runtime = tokio::runtime::Handle::current();
    Box::new(move |paused| {
        let participant = participant.clone();
        runtime.spawn(async move {
            let attributes = HashMap::from([(PAUSED_ATTRIBUTE.to_string(), paused.to_string())]);
            if let Err(e) = participant.set_attributes(attributes).await {
                log::warn!("screenshare: telling viewers paused={paused}: {e:?}");
            }
        });
    })
}

/// Stop a capture off the async runtime, and hand back the reason it is being
/// stopped so the error path reads as one expression.
async fn stop_capture(capture: Capture, reason: String) -> String {
    let _ = tokio::task::spawn_blocking(move || capture.stop()).await;
    reason
}
