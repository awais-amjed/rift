//! A real share into a real room, watched by a real viewer.
//!
//! Ignored by default: it needs a LiveKit server and a display. Run it by
//! hand with the server's credentials in the environment:
//!
//! ```text
//! LIVEKIT_URL=ws://localhost:7880 LIVEKIT_API_KEY=… LIVEKIT_API_SECRET=… \
//!   cargo test live_ -- --ignored --nocapture --test-threads=1
//! ```
//!
//! Under a Wayland session libwebrtc captures through the desktop portal,
//! which waits for a click nobody is there to give; set
//! `XDG_SESSION_TYPE=x11` as well to take the X11 capturer on Xwayland.
//!
//! What it proves that the unit tests cannot: the capturer delivers frames on
//! this machine, the track publishes, the viewer decrypts it — which is only
//! true if the sender's cryptor is on the slot the key was set in — and a
//! session can be refused, stopped, and stopped again.
use super::session;
use crate::api::screenshare::types::{ScreenShareConfig, ShareCursor, SharePriority, VideoCodec};
use futures_util::StreamExt;
use livekit::e2ee::key_provider::{KeyProvider, KeyProviderOptions};
use livekit::e2ee::{E2eeOptions, EncryptionType};
use livekit::prelude::*;
use livekit::webrtc::video_stream::native::NativeVideoStream;
use livekit_api::access_token::{AccessToken, VideoGrants};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::timeout;

/// Not slot 0, so a sender that ignores the index cannot pass by accident.
pub(crate) const KEY_INDEX: i32 = 3;
const FRAMES_WANTED: usize = 10;
const WAIT: Duration = Duration::from_secs(20);

pub(crate) struct Server {
    pub url: String,
    key: String,
    secret: String,
}

impl Server {
    pub(crate) fn from_env() -> Server {
        let var = |name: &str| {
            std::env::var(name).unwrap_or_else(|_| panic!("{name} is not set; see the module doc"))
        };
        Server {
            url: var("LIVEKIT_URL"),
            key: var("LIVEKIT_API_KEY"),
            secret: var("LIVEKIT_API_SECRET"),
        }
    }

    /// [subscribe] is false for the sharer, as `get_channel_token` mints a
    /// share: the share connection only publishes, and one that could
    /// subscribe was a way to sit in a call as nothing but a "screen share"
    /// that no roster lists.
    pub(crate) fn token(&self, room: &str, identity: &str, subscribe: bool) -> String {
        AccessToken::with_api_key(&self.key, &self.secret)
            .with_identity(identity)
            .with_name(identity)
            .with_grants(VideoGrants {
                room_join: true,
                room: room.to_string(),
                can_publish: Some(true),
                can_subscribe: Some(subscribe),
                can_update_own_metadata: Some(true),
                ..Default::default()
            })
            .to_jwt()
            .expect("token")
    }
}

pub(crate) fn shared_key() -> Vec<u8> {
    (0..32).collect()
}

fn config(server: &Server, room: &str) -> ScreenShareConfig {
    // A share reads its index back through the last list shown, as the
    // dialog's pick is; show one, so index 0 is the first screen.
    super::sources::list(true);
    ScreenShareConfig {
        gpu_capture: true,
        livekit_url: server.url.clone(),
        livekit_token: server.token(room, "sharer", false),
        resolution: 720,
        fps: 15,
        bitrate: 2,
        share_audio: false,
        capture_full_screen: true,
        selected_video_source_index: Some(0),
        portal_choice: None,
        codec: VideoCodec::VP8,
        priority: SharePriority::Smoothness,
        cursor: ShareCursor::Always,
        selected_audio_source: None,
        selected_audio_source_pid: None,
        e2ee_key: shared_key(),
        e2ee_key_index: KEY_INDEX,
    }
}

async fn viewer(
    server: &Server,
    room: &str,
) -> (Room, tokio::sync::mpsc::UnboundedReceiver<RoomEvent>) {
    viewer_as(server, room, "viewer").await
}

/// A participant that subscribes, holding the share's key.
pub(crate) async fn viewer_as(
    server: &Server,
    room: &str,
    identity: &str,
) -> (Room, tokio::sync::mpsc::UnboundedReceiver<RoomEvent>) {
    let key_provider = KeyProvider::with_shared_key(KeyProviderOptions::default(), shared_key());
    key_provider.set_shared_key(shared_key(), KEY_INDEX);
    let mut options = RoomOptions::default();
    options.encryption = Some(E2eeOptions {
        encryption_type: EncryptionType::Gcm,
        key_provider,
    });
    Room::connect(&server.url, &server.token(room, identity, true), options)
        .await
        .expect("viewer connects")
}

pub(crate) fn fresh_room() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis();
    format!("rift-share-test-{now}")
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a display"]
async fn live_share_is_decoded_by_a_viewer_then_stops_cleanly() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = fresh_room();
    let (viewer, mut events) = viewer(&server, &room).await;

    let started = session::start(config(&server, &room))
        .await
        .expect("share starts");
    assert!(started.contains(&room), "{started}");

    let err = session::start(config(&server, &room)).await.unwrap_err();
    assert!(err.contains("Already sharing"), "{err}");

    let track = timeout(WAIT, async {
        loop {
            if let RoomEvent::TrackSubscribed {
                track: RemoteTrack::Video(track),
                ..
            } = events.recv().await.expect("room events")
            {
                break track;
            }
        }
    })
    .await
    .expect("the viewer sees the screen-share track");

    let mut stream = NativeVideoStream::new(track.rtc_track());
    let mut frames = 0;
    let mut size = (0, 0);
    timeout(WAIT, async {
        while let Some(frame) = stream.next().await {
            frames += 1;
            size = (frame.buffer.width(), frame.buffer.height());
            if frames >= FRAMES_WANTED {
                break;
            }
        }
    })
    .await
    .expect("decoded frames keep arriving");
    assert_eq!(frames, FRAMES_WANTED);
    assert!(
        size.1 <= 720 && size.0 % 2 == 0 && size.1 % 2 == 0,
        "{size:?}"
    );
    log::info!(
        "live test: viewer decoded {frames} frames at {}x{}",
        size.0,
        size.1
    );

    assert_eq!(session::stop().await.unwrap(), "Stopped successfully");
    assert_eq!(session::stop().await.unwrap(), "No active session");
    viewer.close().await.unwrap();
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server"]
async fn live_bad_token_fails_and_leaves_nothing_running() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let mut config = config(&server, &fresh_room());
    config.livekit_token = "not-a-token".to_string();

    let err = session::start(config).await.unwrap_err();
    assert!(err.contains("Failed to connect"), "{err}");
    assert_eq!(session::stop().await.unwrap(), "No active session");
}

/// A still screen on Windows 10's capturer (DXGI) is sent again once a second
/// rather than at the share's rate, and still reaches the viewer
/// (`capture::StillScreen`). Windows 11 captures a screen this way with
/// `RIFT_SCREENS_ON_DXGI=1`, which the test sets. Run it on the desktop, not
/// over SSH, and leave the mouse alone: DXGI sees only the signed-in session,
/// and a moved cursor is a change.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a Windows desktop"]
async fn live_a_still_dxgi_screen_is_sent_once_a_second() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    // Before anything asks which capturer a screen gets: the answer is kept.
    std::env::set_var("RIFT_SCREENS_ON_DXGI", "1");
    let server = Server::from_env();
    let room = fresh_room();
    let (viewer, mut events) = viewer(&server, &room).await;
    let mut config = config(&server, &room);
    // libwebrtc's capturer, as a share whose encoder reads memory has.
    config.gpu_capture = false;
    config.fps = 30;
    session::start(config).await.expect("share starts");

    let track = timeout(WAIT, async {
        loop {
            if let RoomEvent::TrackSubscribed {
                track: RemoteTrack::Video(track),
                ..
            } = events.recv().await.expect("room events")
            {
                break track;
            }
        }
    })
    .await
    .expect("the viewer sees the screen-share track");

    // The quick repeats after the first picture, then the settled ones.
    let mut stream = NativeVideoStream::new(track.rtc_track());
    let first = pictures_in(&mut stream, Duration::from_secs(3)).await;
    let settled = pictures_in(&mut stream, Duration::from_secs(6)).await;
    log::info!("live test: {first} pictures in the first 3 s, {settled} in the 6 s after");
    assert!(first > 0, "the viewer got no picture");
    // 30 fps would be 180; once a second is 6, and the taskbar clock or a
    // notification may change something.
    assert!(
        (1..=20).contains(&settled),
        "{settled} pictures in 6 s of a still screen"
    );

    assert_eq!(session::stop().await.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// How many pictures the viewer decodes in the next `wait`.
#[cfg(target_os = "windows")]
async fn pictures_in(stream: &mut NativeVideoStream, wait: Duration) -> u32 {
    let until = tokio::time::Instant::now() + wait;
    let mut pictures = 0;
    while let Ok(Some(_)) = tokio::time::timeout_at(until, stream.next()).await {
        pictures += 1;
    }
    pictures
}
