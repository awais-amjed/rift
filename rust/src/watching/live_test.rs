//! A share watched through the watch connection, against a real LiveKit.
//!
//! Ignored by default; run as `screenshare::live_test` says, with the server's
//! credentials in the environment:
//!
//! ```text
//! cargo test --release live_watch_ -- --ignored --nocapture --test-threads=1
//! ```
//!
//! The share is a synthetic one, a flat picture of a known shade published
//! from Rust as a screen share, so no display is needed. What it proves: a
//! watched share's pictures reach the runner's slot in the right size and
//! shade, through the call's key; unwatching stops the marks and watching
//! again starts them; and a share sealed under a key the call rotated to is
//! read once that key is added.
//!
//! The sound test plays out loud, so it plays only into a test sink, and is
//! run on its own (Linux):
//!
//! ```text
//! pactl load-module module-null-sink sink_name=rift_watch_test \
//!     sink_properties=device.description=rift_watch_test
//! PULSE_SINK=rift_watch_test RIFT_WATCH_TEST_OUTPUT=rift_watch_test \
//!     cargo test --release live_watched_sound -- --ignored --nocapture
//! ```
//!
//! `PULSE_SINK` keeps anything that falls back to the default in the sink
//! too. It is heard by recording the sink's monitor beside it: a 1 kHz tone
//! in the left ear, then the right, a second each, for four seconds at full
//! volume, two at nothing and three at half, then unwatched. The test logs
//! when each begins.
use super::{frames, session, sound};
use crate::api::watching::WatchRoom;
use crate::screenshare::live_test::{shared_key, Server, KEY_INDEX};
use crate::sharing::room;
use livekit::options::{TrackPublishOptions, VideoCodec, VideoEncoding};
use livekit::prelude::*;
use livekit::webrtc::prelude::{I420Buffer, VideoFrame, VideoResolution, VideoRotation};
use livekit::webrtc::video_source::native::NativeVideoSource;
use livekit::webrtc::video_source::RtcVideoSource;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const WIDTH: u32 = 640;
const HEIGHT: u32 = 360;
const FPS: u32 = 30;
const SHADE: u8 = 200;

static MARKS: [AtomicU64; 4] = [const { AtomicU64::new(0) }; 4];

unsafe extern "C" fn count_mark(texture: u64) {
    MARKS[texture as usize].fetch_add(1, Ordering::SeqCst);
}

fn mark_address() -> usize {
    let mark: super::frames::MarkFn = count_mark;
    mark as usize
}

fn marks(texture: u64) -> u64 {
    MARKS[texture as usize].load(Ordering::SeqCst)
}

fn room_name(what: &str) -> String {
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis();
    format!("rift-watch-test-{what}-{ms}")
}

/// A member's share: a flat [SHADE] picture, sealed with [key] in [index],
/// until [stop] is set.
struct Share {
    room: Room,
    stop: Arc<AtomicBool>,
}

impl Share {
    async fn start(
        server: &Server,
        room_name: &str,
        identity: &str,
        key: &[u8],
        index: i32,
    ) -> Share {
        let room = room::connect(
            &server.url,
            &server.token(room_name, identity, false),
            key,
            index,
        )
        .await
        .expect("sharer connects");
        let source = NativeVideoSource::new(
            VideoResolution {
                width: WIDTH,
                height: HEIGHT,
            },
            false,
        );
        let track = LocalVideoTrack::create_video_track(
            "screen_share",
            RtcVideoSource::Native(source.clone()),
        );
        room.local_participant()
            .publish_track(
                LocalTrack::Video(track),
                TrackPublishOptions {
                    source: TrackSource::Screenshare,
                    video_codec: VideoCodec::VP8,
                    simulcast: false,
                    video_encoding: Some(VideoEncoding {
                        max_bitrate: 2_000_000,
                        max_framerate: f64::from(FPS),
                    }),
                    ..Default::default()
                },
            )
            .await
            .expect("publishes");
        let stop = Arc::new(AtomicBool::new(false));
        let stopping = stop.clone();
        tokio::task::spawn_blocking(move || {
            while !stopping.load(Ordering::SeqCst) {
                let mut buffer = I420Buffer::new(WIDTH, HEIGHT);
                let (y, u, v) = buffer.data_mut();
                y.fill(SHADE);
                u.fill(128);
                v.fill(128);
                source.capture_frame(&VideoFrame::new(VideoRotation::VideoRotation0, buffer));
                std::thread::sleep(Duration::from_millis(1000 / u64::from(FPS)));
            }
        });
        Share { room, stop }
    }

    async fn end(self) {
        self.stop.store(true, Ordering::SeqCst);
        let _ = self.room.close().await;
    }
}

/// A failed assertion still stops the picture, or the test's runtime waits
/// for its thread for ever.
impl Drop for Share {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
    }
}

/// Opens the watch connection, after the voice connection it belongs to: a
/// server with LiveKit's webhook removes a `_watch` connection whose device
/// is not in the call (`livekit_webhook`), as it would an orphan. The voice
/// connection is returned, to be held for the test.
async fn start_watching(server: &Server, room_name: &str, key: Vec<u8>, index: i32) -> Room {
    let (voice, _) = Room::connect(
        &server.url,
        &server.token(room_name, "watcher~laptop", false),
        RoomOptions::default(),
    )
    .await
    .expect("the voice connection joins");
    session::start(WatchRoom {
        livekit_url: server.url.clone(),
        livekit_token: server.token(room_name, "watcher~laptop_watch", true),
        e2ee_key: key,
        e2ee_key_index: index,
    })
    .await
    .expect("the watch connection opens");
    voice
}

/// Waits until [texture] has been marked [more] times past [from].
async fn marked(texture: u64, from: u64, more: u64, within: Duration) -> bool {
    let until = Instant::now() + within;
    while Instant::now() < until {
        if marks(texture) >= from + more {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    false
}

/// The picture waiting for [texture], as the runner would read it: its size
/// and the shade in the middle.
fn drawn(texture: u64) -> Option<(u32, u32, u8)> {
    let mut planes = std::mem::MaybeUninit::<frames::WatchPlanes>::uninit();
    // SAFETY: a WatchPlanes this test owns.
    if unsafe { frames::rift_watch_frame_lock(texture, planes.as_mut_ptr()) } == 0 {
        return None;
    }
    // SAFETY: written, since lock answered 1.
    let planes = unsafe { planes.assume_init() };
    let middle = (planes.height / 2 * planes.stride_y + planes.width / 2) as usize;
    // SAFETY: the picture is lent until the unlock below.
    let shade = unsafe { *planes.y.add(middle) };
    frames::rift_watch_frame_unlock(texture);
    Some((planes.width, planes.height, shade))
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server; see the module doc"]
async fn live_watch_draws_a_watched_share_and_stops_when_unwatched() {
    let _ = env_logger::builder().is_test(true).try_init();
    let server = Server::from_env();
    let name = room_name("draw");
    let key = shared_key();
    let share_identity = "member~desk_share";
    const TEXTURE: u64 = 1;

    // Watched before it is published: the room's event subscribes it.
    let _voice = start_watching(&server, &name, key.clone(), KEY_INDEX).await;
    session::watch(share_identity.to_string(), TEXTURE, mark_address())
        .await
        .expect("watches");
    let share = Share::start(&server, &name, share_identity, &key, KEY_INDEX).await;

    assert!(
        marked(TEXTURE, 0, 30, Duration::from_secs(15)).await,
        "pictures reach the runner's slot ({} marks)",
        marks(TEXTURE)
    );
    let (width, height, shade) = drawn(TEXTURE)
        .or_else(|| {
            std::thread::sleep(Duration::from_millis(100));
            drawn(TEXTURE)
        })
        .expect("a picture waiting");
    log::info!("watch test: {width}x{height}, shade {shade}");
    assert_eq!((width, height), (WIDTH, HEIGHT));
    assert!(
        shade.abs_diff(SHADE) <= 4,
        "the shade sent, not noise: {shade}"
    );

    // Unwatched: no more marks.
    session::unwatch(share_identity).await;
    let after = marks(TEXTURE);
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(marks(TEXTURE), after, "nothing marks a texture let go");

    // Watched again, already published: subscribed straight away.
    session::watch(share_identity.to_string(), TEXTURE, mark_address())
        .await
        .expect("watches again");
    assert!(
        marked(TEXTURE, after, 30, Duration::from_secs(15)).await,
        "pictures come back when watched again"
    );

    session::stop().await;
    let stopped = marks(TEXTURE);
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(marks(TEXTURE), stopped, "nothing marks after a stop");
    share.end().await;
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server; see the module doc"]
async fn live_watch_reads_a_share_sealed_after_a_rotation() {
    let _ = env_logger::builder().is_test(true).try_init();
    let server = Server::from_env();
    let name = room_name("rotate");
    let old_key = shared_key();
    let new_key: Vec<u8> = old_key.iter().map(|b| b ^ 0x5a).collect();
    let new_index = KEY_INDEX + 1;
    const OLD: u64 = 2;
    const NEW: u64 = 3;

    let _voice = start_watching(&server, &name, old_key.clone(), KEY_INDEX).await;
    let before = Share::start(&server, &name, "early~desk_share", &old_key, KEY_INDEX).await;
    let after = Share::start(&server, &name, "late~desk_share", &new_key, new_index).await;
    session::watch("early~desk_share".into(), OLD, mark_address())
        .await
        .unwrap();
    session::watch("late~desk_share".into(), NEW, mark_address())
        .await
        .unwrap();

    assert!(
        marked(OLD, 0, 30, Duration::from_secs(15)).await,
        "the share on the old key is read"
    );
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(marks(NEW), 0, "a share on a key not given is not read");

    session::add_key(new_key, new_index)
        .await
        .expect("key added");
    assert!(
        marked(NEW, 0, 30, Duration::from_secs(15)).await,
        "the share on the new key is read once it is added"
    );
    let shade = drawn(NEW).map(|(_, _, shade)| shade).unwrap_or_default();
    assert!(
        shade.abs_diff(SHADE) <= 4,
        "decrypted, not garbage: {shade}"
    );
    assert!(
        marked(OLD, marks(OLD), 30, Duration::from_secs(5)).await,
        "and the old one still is"
    );

    session::stop().await;
    before.end().await;
    after.end().await;
}

/// Interleaved stereo for frame [index] of 10 ms: a 1 kHz tone in the left
/// ear for a second, then in the right.
fn tone_frame(index: u32) -> Vec<i16> {
    use crate::sharing::audio::SAMPLE_RATE;
    let per_frame = SAMPLE_RATE / 100;
    let left = (index / 100) % 2 == 0;
    let mut samples = Vec::with_capacity(per_frame as usize * 2);
    for i in 0..per_frame {
        let t = f64::from(index * per_frame + i) / f64::from(SAMPLE_RATE);
        let v = ((t * 1_000.0 * std::f64::consts::TAU).sin() * 8_000.0) as i16;
        let (l, r) = if left { (v, 0) } else { (0, v) };
        samples.push(l);
        samples.push(r);
    }
    samples
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a test sink; see the module doc"]
async fn live_watched_sound_plays_in_stereo_at_its_volume() {
    use crate::sharing::audio::{publish_and_feed, Command, Pcm, SpawnCapture};
    let _ = env_logger::builder().is_test(true).try_init();
    let output = std::env::var("RIFT_WATCH_TEST_OUTPUT")
        .expect("RIFT_WATCH_TEST_OUTPUT names a test sink; see the module doc");
    assert!(output.starts_with("rift_"), "only into a rift_ test sink");
    assert_eq!(
        std::env::var("PULSE_SINK").as_deref(),
        Ok(output.as_str()),
        "PULSE_SINK is the test sink too, so a fallback stays in it"
    );
    let mut connection = crate::pulse::Connection::open("rift-watch-test").expect("pulse");
    assert!(
        crate::pulse::sink_for(&mut connection, Some(&output)).is_some(),
        "the test sink is there"
    );
    drop(connection);
    sound::set_output(Some(output));

    let server = Server::from_env();
    let name = room_name("sound");
    let key = shared_key();
    let share_identity = "member~desk_share";
    const TEXTURE: u64 = 0;

    let _voice = start_watching(&server, &name, key.clone(), KEY_INDEX).await;
    session::watch(share_identity.to_string(), TEXTURE, mark_address())
        .await
        .expect("watches");
    session::set_volume(share_identity, 1.0).await;
    let share = Share::start(&server, &name, share_identity, &key, KEY_INDEX).await;
    let spawn: SpawnCapture = Box::new(|commands, frames| {
        std::thread::spawn(move || {
            let start = Instant::now();
            for index in 0.. {
                if commands
                    .try_recv()
                    .is_ok_and(|c| matches!(c, Command::Terminate))
                {
                    return;
                }
                let due = start + Duration::from_millis(u64::from(index) * 10);
                std::thread::sleep(due.saturating_duration_since(Instant::now()));
                if frames
                    .blocking_send(Pcm::read_now(tone_frame(index)))
                    .is_err()
                {
                    return;
                }
            }
        })
    });
    let feed = publish_and_feed(&share.room, spawn, "share-sound", None)
        .await
        .expect("the sound publishes");
    assert!(
        marked(TEXTURE, 0, 10, Duration::from_secs(15)).await,
        "the picture arrives"
    );

    let at = |what: &str| {
        let ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis();
        log::info!("sound test: {what} at {ms}");
    };
    at("full");
    tokio::time::sleep(Duration::from_secs(4)).await;
    session::set_volume(share_identity, 0.0).await;
    at("nothing");
    tokio::time::sleep(Duration::from_secs(2)).await;
    session::set_volume(share_identity, 0.5).await;
    at("half");
    tokio::time::sleep(Duration::from_secs(3)).await;
    session::unwatch(share_identity).await;
    at("unwatched");
    tokio::time::sleep(Duration::from_secs(1)).await;

    feed.terminate();
    session::stop().await;
    share.end().await;
}
