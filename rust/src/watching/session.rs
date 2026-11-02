//! The watch connection: one per call, open while the app watches through it.
//!
//! It subscribes to nothing by itself (`auto_subscribe` off). Watching a share
//! subscribes to that share's picture, and every picture goes to the texture
//! the runner made for it ([`super::frames`]). Not watching it any more
//! unsubscribes again: a picture may be, where a call's sound must never be
//! (`CALLS.md`, *Receiving a call's audio*).
use super::frames::{self, MarkFn};
use crate::api::watching::{emit_watch_event, WatchEvent, WatchEventKind, WatchRoom};
use crate::sharing::room;
use futures_util::StreamExt;
use livekit::prelude::*;
use livekit::webrtc::prelude::VideoBuffer;
use livekit::webrtc::video_stream::native::NativeVideoStream;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

const KEY_BYTES: usize = 32;

/// One watched share: the runner's texture, and the task feeding it while its
/// picture track is subscribed.
struct Watched {
    texture: u64,
    picture: Option<JoinHandle<()>>,
}

/// What both the bridge's calls and the room's events change, keyed by the
/// share's identity (`<user>~<device>_share`).
type Shares = Arc<StdMutex<HashMap<String, Watched>>>;

struct Session {
    room: Room,
    shares: Shares,
    events: JoinHandle<()>,
}

// Held for the whole of a start or a stop, as a share's session is, so a stop
// during a start cannot leave a connection open that nobody can reach.
static SESSION: Mutex<Option<Session>> = Mutex::const_new(None);

/// Whether pictures are wanted at all: off while nobody can see Rift, so the
/// server stops sending them and nothing is decoded (`CALLS.md`, *Watching
/// while Rift cannot be seen*). Kept apart from the session, since a share
/// subscribed while Rift is hidden has to start off.
static PICTURES_ON: AtomicBool = AtomicBool::new(true);

fn lock(shares: &Shares) -> std::sync::MutexGuard<'_, HashMap<String, Watched>> {
    shares.lock().unwrap_or_else(|e| e.into_inner())
}

pub(crate) async fn start(config: WatchRoom) -> Result<(), String> {
    if config.e2ee_key.len() != KEY_BYTES {
        return Err("Missing the channel key for this call".to_string());
    }
    let mut slot = SESSION.lock().await;
    if let Some(old) = slot.take() {
        close(old).await;
    }

    let mut options = room::encrypted_options(&config.e2ee_key, config.e2ee_key_index);
    options.auto_subscribe = false;
    let (room, events) = Room::connect(&config.livekit_url, &config.livekit_token, options)
        .await
        .map_err(|e| format!("Failed to connect to LiveKit: {e:?}"))?;
    log::info!("watching: connected to room {}", room.name());

    let shares: Shares = Arc::default();
    let events = tokio::spawn(follow_room(events, shares.clone()));
    *slot = Some(Session {
        room,
        shares,
        events,
    });
    Ok(())
}

pub(crate) async fn stop() {
    if let Some(session) = SESSION.lock().await.take() {
        close(session).await;
        log::info!("watching: stopped");
    }
}

async fn close(session: Session) {
    session.events.abort();
    for (_, watched) in lock(&session.shares).drain() {
        let_go(watched);
    }
    if let Err(e) = session.room.close().await {
        log::warn!("watching: disconnect reported {e:?}");
    }
}

/// Stop feeding a texture, and stop marking it before this returns.
fn let_go(watched: Watched) {
    if let Some(task) = watched.picture {
        task.abort();
    }
    frames::close(watched.texture);
}

pub(crate) async fn watch(identity: String, texture: u64, mark: usize) -> Result<(), String> {
    if mark == 0 {
        return Err("No texture to draw the share into".to_string());
    }
    // SAFETY: the address of the runner's mark function, as it gave it to Dart.
    let mark: MarkFn = unsafe { std::mem::transmute::<usize, MarkFn>(mark) };
    let slot = SESSION.lock().await;
    let Some(session) = slot.as_ref() else {
        return Err("Not connected to watch".to_string());
    };

    frames::open(texture, mark);
    if let Some(old) = lock(&session.shares).insert(
        identity.clone(),
        Watched {
            texture,
            picture: None,
        },
    ) {
        if old.texture != texture {
            let_go(old);
        } else if let Some(task) = old.picture {
            task.abort();
        }
    }

    // Already published: subscribe now, or show it if it is subscribed
    // already. Published later, the room's event does it.
    let participant = session
        .room
        .remote_participants()
        .get(&ParticipantIdentity(identity.clone()))
        .cloned();
    if let Some(participant) = participant {
        for publication in participant.track_publications().into_values() {
            if publication.kind() != TrackKind::Video {
                continue;
            }
            match publication.track() {
                Some(RemoteTrack::Video(track)) => show(&session.shares, &identity, track),
                _ => publication.set_subscribed(true),
            }
        }
    }
    log::info!("watching: a share");
    Ok(())
}

pub(crate) async fn unwatch(identity: &str) {
    let slot = SESSION.lock().await;
    let Some(session) = slot.as_ref() else { return };
    let Some(watched) = lock(&session.shares).remove(identity) else {
        return;
    };
    let_go(watched);
    if let Some(participant) = session
        .room
        .remote_participants()
        .get(&ParticipantIdentity(identity.to_string()))
    {
        for publication in participant.track_publications().into_values() {
            if publication.kind() == TrackKind::Video && publication.is_subscribed() {
                publication.set_subscribed(false);
            }
        }
    }
    log::info!("watching: no longer a share");
}

pub(crate) async fn add_key(key: Vec<u8>, index: i32) -> Result<(), String> {
    if key.len() != KEY_BYTES {
        return Err("Missing the channel key for this call".to_string());
    }
    let slot = SESSION.lock().await;
    let Some(session) = slot.as_ref() else {
        return Ok(());
    };
    let Some(provider) = session.room.e2ee_manager().key_provider() else {
        return Err("The watch connection has no key ring".to_string());
    };
    provider.set_shared_key(key, index);
    Ok(())
}

/// Turns every watched picture on or off, without unwatching: the share
/// stays subscribed, as a deafen leaves a voice subscribed. A picture only
/// subscribed later takes the same setting as it arrives ([`follow_room`]).
pub(crate) async fn set_pictures_on(on: bool) {
    PICTURES_ON.store(on, Ordering::SeqCst);
    let slot = SESSION.lock().await;
    let Some(session) = slot.as_ref() else { return };
    let watched: Vec<String> = lock(&session.shares).keys().cloned().collect();
    for identity in watched {
        if let Some(participant) = session
            .room
            .remote_participants()
            .get(&ParticipantIdentity(identity))
        {
            for publication in participant.track_publications().into_values() {
                if publication.kind() == TrackKind::Video {
                    publication.set_enabled(on);
                }
            }
        }
    }
    log::info!("watching: pictures {}", if on { "on" } else { "off" });
}

/// Feed [track]'s pictures to the texture watching [identity], replacing a
/// feed already running. Nothing when it is no longer watched.
fn show(shares: &Shares, identity: &str, track: RemoteVideoTrack) {
    let mut shares = lock(shares);
    let Some(watched) = shares.get_mut(identity) else {
        return;
    };
    if let Some(task) = watched.picture.take() {
        task.abort();
    }
    let texture = watched.texture;
    let identity = identity.to_string();
    watched.picture = Some(tokio::spawn(async move {
        // libwebrtc's sink keeps the newest picture and drops the rest, as the
        // slot does: neither side ever queues behind a slow one.
        let mut stream = NativeVideoStream::new(track.rtc_track());
        let mut size = (0, 0);
        while let Some(frame) = stream.next().await {
            // The decoder's own I420 buffer, not a copy: libwebrtc's ToI420 on
            // an I420 buffer answers the buffer itself.
            let picture = frame.buffer.to_i420();
            let now = (picture.width(), picture.height());
            if now != size {
                size = now;
                log::info!("watching: picture {}x{}", now.0, now.1);
                emit_watch_event(WatchEvent {
                    kind: WatchEventKind::PictureSize,
                    share_identity: identity.clone(),
                    width: now.0,
                    height: now.1,
                    reason: String::new(),
                });
            }
            if !frames::deliver(texture, picture) {
                break;
            }
        }
    }));
}

/// The room's side: a watched share publishing, its picture arriving or going,
/// and the connection ending.
async fn follow_room(mut events: tokio::sync::mpsc::UnboundedReceiver<RoomEvent>, shares: Shares) {
    while let Some(event) = events.recv().await {
        match event {
            RoomEvent::TrackPublished {
                publication,
                participant,
            } => {
                let watched = lock(&shares).contains_key(participant.identity().as_str());
                if watched && publication.kind() == TrackKind::Video {
                    publication.set_subscribed(true);
                }
            }
            RoomEvent::TrackSubscribed {
                track: RemoteTrack::Video(track),
                publication,
                participant,
            } => {
                // `set_enabled` only reaches a subscribed track, so a picture
                // subscribed while Rift is hidden is turned off here.
                if !PICTURES_ON.load(Ordering::SeqCst) {
                    publication.set_enabled(false);
                }
                show(&shares, participant.identity().as_str(), track)
            }
            RoomEvent::TrackUnsubscribed {
                track: RemoteTrack::Video(_),
                participant,
                ..
            } => {
                if let Some(watched) = lock(&shares).get_mut(participant.identity().as_str()) {
                    if let Some(task) = watched.picture.take() {
                        task.abort();
                    }
                }
            }
            RoomEvent::Reconnecting => log::info!("watching: reconnecting"),
            RoomEvent::Reconnected => log::info!("watching: reconnected"),
            RoomEvent::Disconnected { reason } => {
                log::warn!("watching: disconnected ({reason:?})");
                emit_watch_event(WatchEvent {
                    kind: WatchEventKind::Lost,
                    share_identity: String::new(),
                    width: 0,
                    height: 0,
                    reason: format!("{reason:?}"),
                });
                break;
            }
            _ => {}
        }
    }
}
