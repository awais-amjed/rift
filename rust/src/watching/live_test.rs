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
use super::{frames, session};
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
