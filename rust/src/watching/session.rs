//! The watch connection: one per call, open while the app watches through it.
//!
//! It subscribes to nothing by itself (`auto_subscribe` off). Watching a share
//! subscribes to that share's picture and its sound. Every picture goes to the
//! texture the runner made for it ([`super::frames`]), decoded on the GPU
//! where it can be ([`super::decode`]) and by libwebrtc where not; the sound
//! is played here ([`super::sound`]). Not watching it any more unsubscribes again. The
//! call's connection must never do that to a sound, because flutter_webrtc
//! finds a sound's decryptor by an id two receivers can share (`CALLS.md`,
//! *Receiving a call's audio*). This SDK hands the decryptor the receiver
//! itself, so here it is safe.
use super::decode;
use super::frames::{self, MarkFn};
use super::sound::{self, Gain, Playing};
use crate::api::watching::{emit_watch_event, WatchEvent, WatchEventKind, WatchRoom, WatchStats};
use crate::sharing::room;
use futures_util::StreamExt;
use livekit::prelude::*;
use livekit::webrtc::prelude::VideoBuffer;
use livekit::webrtc::video_stream::native::NativeVideoStream;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

const KEY_BYTES: usize = 32;

/// One watched share: the runner's texture and what feeds it while its
/// picture is subscribed, and its sound playing while that is.
struct Watched {
    texture: u64,
    picture: Option<PictureFeed>,
    /// How loud the app wants the sound; kept from before it arrives.
    gain: Arc<Gain>,
    sound: Option<Playing>,
}

/// A share's pictures on their way to its texture. Dropped, they stop.
enum PictureFeed {
    /// Decoded by libwebrtc, read on the runtime.
    Decoded(JoinHandle<()>),
    /// Read still encoded and decoded on the GPU, on a thread of its own;
    /// held only to stop it.
    Encoded { _feed: decode::Feed },
}

impl Drop for PictureFeed {
    fn drop(&mut self) {
        if let PictureFeed::Decoded(task) = self {
            task.abort();
        }
    }
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

/// Stop feeding a texture, and stop marking it before this returns. The
/// sound stops as `watched` goes.
fn let_go(mut watched: Watched) {
    watched.picture = None;
    frames::close(watched.texture);
}

pub(crate) async fn watch(
    identity: String,
    texture: u64,
    mark: usize,
    takes_gpu_pictures: bool,
) -> Result<(), String> {
    if mark == 0 {
        return Err("No texture to draw the share into".to_string());
    }
    // Asked at each watch, so a refusal lasts only as long as its reason.
    if let Some(gpu) = decode::gpu() {
        if !takes_gpu_pictures || !gpu.drawn_by_runner() {
            return Err("This window cannot draw a picture decoded on the GPU".to_string());
        }
    }
    // SAFETY: the address of the runner's mark function, as it gave it to Dart.
    let mark: MarkFn = unsafe { std::mem::transmute::<usize, MarkFn>(mark) };
    let slot = SESSION.lock().await;
    let Some(session) = slot.as_ref() else {
        return Err("Not connected to watch".to_string());
    };

    frames::open(texture, mark);
    let mut shares = lock(&session.shares);
    // Watched again: the sound keeps the volume it was given.
    let gain = shares
        .get(&identity)
        .map(|old| old.gain.clone())
        .unwrap_or_default();
    let old = shares.insert(
        identity.clone(),
        Watched {
            texture,
            picture: None,
            gain,
            sound: None,
        },
    );
    drop(shares);
    if let Some(old) = old {
        if old.texture != texture {
            let_go(old);
        }
    }

    // Already published: subscribe now, or show and play it if it is
    // subscribed already. Published later, the room's event does it.
    let participant = session
        .room
        .remote_participants()
        .get(&ParticipantIdentity(identity.clone()))
        .cloned();
    if let Some(participant) = participant {
        for publication in participant.track_publications().into_values() {
            if !wanted(&publication) {
                continue;
            }
            match publication.track() {
                Some(RemoteTrack::Video(track)) => show(&session.shares, &identity, track),
                Some(RemoteTrack::Audio(track)) => play(&session.shares, &identity, track),
                None => publication.set_subscribed(true),
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
            if publication.is_subscribed() {
                publication.set_subscribed(false);
            }
        }
    }
    log::info!("watching: no longer a share");
}

/// [identity]'s picture's receive numbers (`super::stats`), or None while it
/// is not arriving. The track is read out under the lock and asked after it,
/// so a poll never holds up a watch or an unwatch.
pub(crate) async fn stats(identity: &str) -> Option<WatchStats> {
    let track = {
        let slot = SESSION.lock().await;
        let session = slot.as_ref()?;
        if !lock(&session.shares).contains_key(identity) {
            return None;
        }
        let participant = session
            .room
            .remote_participants()
            .get(&ParticipantIdentity(identity.to_string()))
            .cloned()?;
        participant
            .track_publications()
            .into_values()
            .find_map(|publication| match publication.track() {
                Some(RemoteTrack::Video(track)) => Some(track),
                _ => None,
            })?
    };
    let reports = track.get_stats().await.ok()?;
    super::stats::received(&reports)
}

/// Sets how loud [identity]'s sound plays: the share's own volume times the
/// call's, or nothing (muted, deafened). At nothing the server is told to stop
/// sending it, as the call holds a sound nobody hears.
pub(crate) async fn set_volume(identity: &str, volume: f32) {
    let slot = SESSION.lock().await;
    let Some(session) = slot.as_ref() else { return };
    let Some(gain) = lock(&session.shares).get(identity).map(|w| w.gain.clone()) else {
        return;
    };
    gain.set(volume);
    if let Some(participant) = session
        .room
        .remote_participants()
        .get(&ParticipantIdentity(identity.to_string()))
    {
        for publication in participant.track_publications().into_values() {
            if publication.source() == TrackSource::ScreenshareAudio {
                publication.set_enabled(volume > 0.0);
            }
        }
    }
}

/// Whether this connection receives `publication` of a watched share: its
/// picture always, its sound where this build plays it.
fn wanted(publication: &RemoteTrackPublication) -> bool {
    wanted_source(publication.source(), sound::PLAYS)
}

/// The share's own tracks and nothing else. A phone shares on the connection
/// it talks on, so its mic and camera sit beside the share: taken here, the
/// mic played a second time over the call's copy, and the camera could take
/// the share's tile.
fn wanted_source(source: TrackSource, plays_sound: bool) -> bool {
    match source {
        TrackSource::Screenshare => true,
        TrackSource::ScreenshareAudio => plays_sound,
        _ => false,
    }
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
    let shares_handle = shares.clone();
    let mut shares = lock(shares);
    let Some(watched) = shares.get_mut(identity) else {
        return;
    };
    watched.picture = None;
    let texture = watched.texture;
    let identity = identity.to_string();
    tokio::spawn(await_picture(shares_handle, identity.clone(), texture));
    if let Some(gpu) = decode::gpu() {
        watched.picture = decode::feed(track, texture, identity, gpu)
            .map(|feed| PictureFeed::Encoded { _feed: feed });
        return;
    }
    watched.picture = Some(PictureFeed::Decoded(tokio::spawn(async move {
        // libwebrtc's sink keeps the newest picture and drops the rest, as the
        // slot does: neither side ever queues behind a slow one.
        let mut stream = NativeVideoStream::new(track.rtc_track());
        let mut size = (0, 0);
        while let Some(frame) = stream.next().await {
            // The decoder's own I420 buffer, not a copy: libwebrtc's ToI420 on
            // an I420 buffer answers the buffer itself.
            let picture = frame.buffer.to_i420();
            picture_size(&identity, &mut size, (picture.width(), picture.height()));
            if !frames::deliver(texture, picture) {
                break;
            }
        }
    })));
}

/// How long a watched share's picture may be on, subscribed, and still show
/// nothing before the call's connection takes it back. Long enough for the
/// keyframe a late viewer asks for and a GPU decoder setting up; anything
/// longer is a share this connection cannot read. One sealed under a key the
/// watch connection was never given decrypts to nothing and says nothing, and
/// the call, whose ring may hold that key, would have shown it.
const NO_PICTURE_WITHIN: Duration = Duration::from_secs(6);
const PICTURE_CHECK: Duration = Duration::from_millis(500);

#[derive(Debug, PartialEq, Eq)]
enum PictureVerdict {
    Waiting,
    Came,
    Starved,
}

/// The time a subscribed picture has been on with nothing shown. Time with
/// pictures off does not count: hidden, nothing is sent.
#[derive(Default)]
struct PictureWait {
    on_for: Duration,
}

impl PictureWait {
    fn tick(&mut self, elapsed: Duration, on: bool, came: bool) -> PictureVerdict {
        if came {
            return PictureVerdict::Came;
        }
        if on {
            self.on_for += elapsed;
        }
        if self.on_for >= NO_PICTURE_WITHIN {
            PictureVerdict::Starved
        } else {
            PictureVerdict::Waiting
        }
    }
}

/// Gives up on the watch connection when [identity]'s picture, subscribed,
/// never comes. Ends when one does, or the share is no longer watched into
/// [texture].
async fn await_picture(shares: Shares, identity: String, texture: u64) {
    let mut wait = PictureWait::default();
    loop {
        tokio::time::sleep(PICTURE_CHECK).await;
        if lock(&shares).get(&identity).map(|w| w.texture) != Some(texture) {
            return;
        }
        let on = PICTURES_ON.load(Ordering::SeqCst);
        match wait.tick(PICTURE_CHECK, on, frames::delivered(texture)) {
            PictureVerdict::Waiting => {}
            PictureVerdict::Came => return,
            PictureVerdict::Starved => {
                log::warn!("watching: no picture from a watched share");
                lost(&format!(
                    "no picture within {} s",
                    NO_PICTURE_WITHIN.as_secs()
                ));
                return;
            }
        }
    }
}

/// Tells the app [identity]'s picture is `now` in size, when that is not
/// what `seen` was.
pub(super) fn picture_size(identity: &str, seen: &mut (u32, u32), now: (u32, u32)) {
    if now == *seen {
        return;
    }
    *seen = now;
    log::info!("watching: picture {}x{}", now.0, now.1);
    emit_watch_event(WatchEvent {
        kind: WatchEventKind::PictureSize,
        share_identity: identity.to_string(),
        width: now.0,
        height: now.1,
        reason: String::new(),
    });
}

/// Tells the app the watch connection cannot go on: it watches through the
/// call's connection again.
pub(super) fn lost(reason: &str) {
    #[cfg(test)]
    LOST.lock()
        .unwrap_or_else(|e| e.into_inner())
        .push(reason.to_string());
    emit_watch_event(WatchEvent {
        kind: WatchEventKind::Lost,
        share_identity: String::new(),
        width: 0,
        height: 0,
        reason: reason.to_string(),
    });
}

/// Every reason the watch connection was lost for, for the tests, which have
/// no app to tell.
#[cfg(test)]
static LOST: StdMutex<Vec<String>> = StdMutex::new(Vec::new());

#[cfg(test)]
pub(super) fn lost_reasons() -> Vec<String> {
    LOST.lock().unwrap_or_else(|e| e.into_inner()).clone()
}

/// Play [track] as [identity]'s sound, replacing one already playing.
/// Nothing when it is no longer watched.
fn play(shares: &Shares, identity: &str, track: RemoteAudioTrack) {
    let mut shares = lock(shares);
    let Some(watched) = shares.get_mut(identity) else {
        return;
    };
    watched.sound = None;
    watched.sound = sound::play(track, watched.gain.clone());
    log::info!("watching: playing a share's sound");
}

/// The room's side: a watched share publishing, its picture or sound arriving
/// or going, and the connection ending.
async fn follow_room(mut events: tokio::sync::mpsc::UnboundedReceiver<RoomEvent>, shares: Shares) {
    while let Some(event) = events.recv().await {
        match event {
            RoomEvent::TrackPublished {
                publication,
                participant,
            } => {
                let watched = lock(&shares).contains_key(participant.identity().as_str());
                if watched && wanted(&publication) {
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
            RoomEvent::TrackSubscribed {
                track: RemoteTrack::Audio(track),
                publication,
                participant,
            } => {
                // Arriving at nothing (muted, deafened, or before the app has
                // said), the server stops sending it until it is turned up.
                let identity = participant.identity();
                let gain = lock(&shares).get(identity.as_str()).map(|w| w.gain.get());
                if gain == Some(0.0) {
                    log::info!("watching: sound arrived at nothing, held");
                    publication.set_enabled(false);
                }
                play(&shares, identity.as_str(), track)
            }
            RoomEvent::TrackUnsubscribed {
                track, participant, ..
            } => {
                if let Some(watched) = lock(&shares).get_mut(participant.identity().as_str()) {
                    match track {
                        RemoteTrack::Video(_) => watched.picture = None,
                        RemoteTrack::Audio(_) => watched.sound = None,
                    }
                }
            }
            RoomEvent::Reconnecting => log::info!("watching: reconnecting"),
            RoomEvent::Reconnected => log::info!("watching: reconnected"),
            RoomEvent::Disconnected { reason } => {
                log::warn!("watching: disconnected ({reason:?})");
                lost(&format!("connection lost: {reason:?}"));
                break;
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_share_with_no_picture_is_given_up_after_its_time_on_screen() {
        let step = Duration::from_millis(500);
        let mut wait = PictureWait::default();
        let mut verdict = PictureVerdict::Waiting;
        // Off counts for nothing: hidden, no picture is sent.
        for _ in 0..40 {
            verdict = wait.tick(step, false, false);
        }
        assert_eq!(verdict, PictureVerdict::Waiting);
        let mut ticks = 0;
        while wait.tick(step, true, false) == PictureVerdict::Waiting {
            ticks += 1;
            assert!(ticks < 100);
        }
        assert_eq!(step * (ticks + 1), NO_PICTURE_WITHIN);

        let mut wait = PictureWait::default();
        wait.tick(step, true, false);
        assert_eq!(wait.tick(step, true, true), PictureVerdict::Came);
    }

    #[test]
    fn a_watch_takes_only_the_share() {
        // A phone shares on the connection it talks on: its mic and camera
        // ride beside the share and are the call's to play, not the watch's.
        assert!(wanted_source(TrackSource::Screenshare, true));
        assert!(wanted_source(TrackSource::ScreenshareAudio, true));
        assert!(!wanted_source(TrackSource::ScreenshareAudio, false));
        assert!(!wanted_source(TrackSource::Microphone, true));
        assert!(!wanted_source(TrackSource::Camera, true));
        assert!(!wanted_source(TrackSource::Unknown, true));
    }
}
