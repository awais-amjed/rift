//! One sound share at a time: bringing it up, and taking it down again.
//!
//! The screen share's sibling ([`crate::screenshare::session`]), and a shorter
//! story: there is no capturer to start, no first frame to wait for and no
//! resolution to negotiate. Connect, publish one audio track, and hold on to
//! the pieces until somebody stops it.
use super::audio::{self, AudioCapture, AudioCaptureHandle, AudioSelection};
use super::room;
use crate::api::soundshare::{self, SoundShareConfig, SoundShareEvent};
use livekit::prelude::*;
use tokio::sync::Mutex;

struct Session {
    room: Room,
    audio: AudioCaptureHandle,
}

// An async mutex, held for the whole of a start or a stop — see
// `screenshare::session` for why that is what keeps a stop during a start from
// leaving a room connected that nobody can reach.
static SESSION: Mutex<Option<Session>> = Mutex::const_new(None);

pub(crate) async fn start(config: SoundShareConfig) -> Result<String, String> {
    soundshare::check(&config)?;
    let mut slot = SESSION.lock().await;
    if slot.is_some() {
        return Err("Already sharing sound".to_string());
    }
    log::info!("sound share: starting");

    let room = room::connect(
        &config.livekit_url,
        &config.livekit_token,
        &config.e2ee_key,
        config.e2ee_key_index,
    )
    .await?;
    let room_name = room.name().to_string();
    let room_sid = room.sid().await.to_string();
    log::info!("sound share: connected to room {room_name} ({room_sid})");

    // The track carries the application's name, which is what everyone else's
    // tile shows; and the application quitting mid-share reaches Flutter as an
    // event rather than as a share that stays up publishing silence.
    let capture = audio::start(
        &room,
        AudioCapture {
            selection: AudioSelection::from(&config),
            track_name: config.source_label.clone(),
            on_ended: Some(Box::new(|| {
                soundshare::emit_event(SoundShareEvent::SourceEnded)
            })),
        },
    )
    .await;

    let Some(audio) = capture else {
        // Leave nothing behind: a room left open here is a ghost participant
        // the app has no handle to.
        if let Err(e) = room.close().await {
            log::warn!("sound share: closing after a failed start: {e:?}");
        }
        return Err("Could not capture that application’s sound".to_string());
    };

    *slot = Some(Session { room, audio });
    log::info!("sound share: started");
    Ok(format!("Connected to room: {room_name} ({room_sid})"))
}

pub(crate) async fn stop() -> Result<String, String> {
    let mut slot = SESSION.lock().await;
    let Some(Session { room, audio }) = slot.take() else {
        log::info!("sound share: stop with nothing running");
        return Ok("No active session".to_string());
    };

    // Room teardown and the capture thread's join run at the same time: the
    // room closing is what tells the room the sound has stopped, and waiting
    // for a PulseAudio thread first would delay that for no one's benefit.
    let (room_result, _) = tokio::join!(
        room.close(),
        tokio::task::spawn_blocking(move || audio.terminate()),
    );
    if let Err(e) = room_result {
        log::warn!("sound share: disconnect reported {e:?}");
    }
    log::info!("sound share: stopped");
    Ok("Stopped successfully".to_string())
}
