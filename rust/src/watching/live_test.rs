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
//! The sound test plays out loud, so it plays only into a test output, and is
//! run on its own. On Linux, a null sink:
//!
//! ```text
//! pactl load-module module-null-sink sink_name=rift_watch_test \
//!     sink_properties=device.description=rift_watch_test
//! PULSE_SINK=rift_watch_test RIFT_WATCH_TEST_OUTPUT=rift_watch_test \
//!     cargo test --release live_watched_sound -- --ignored --nocapture
//! ```
//!
//! The GPU decoding test turns the process's LiveKit runtime to pass-through
//! for good, so it is run on its own too, under Wayland on the GPU that draws
//! the screen (Linux), with Rift's FFmpeg library built by `native/ffenc/build.sh`:
//!
//! ```text
//! WAYLAND_DISPLAY=wayland-0 RIFT_FFENC_LIB=<out>/librift_ffenc.so \
//!     cargo test --release live_gpu_watch -- --ignored --nocapture
//! ```
//!
//! On Windows it decodes on adapter 0, on a device the test makes the way the
//! runner makes its own and puts in the runner's place, with `RIFT_FFENC_LIB`
//! naming the library's `rift_ffenc.dll`.
//!
//! `PULSE_SINK` keeps anything that falls back to the default in the sink
//! too. It is heard by recording the sink's monitor beside it: a 1 kHz tone
//! in the left ear, then the right, a second each, for four seconds at full
//! volume, two at nothing and three at half, then unwatched. The test logs
//! when each begins.
//!
//! On Windows it plays into VB-Cable ("CABLE Input", never the default
//! output) and records the cable's other end itself, through WASAPI, checking
//! each part: the tone in each ear at the level sent, nothing at nothing, 6 dB
//! down at half, and silence once unwatched.
//!
//! ```text
//! cargo test --release live_watched_sound -- --ignored --nocapture --test-threads=1
//! ```
//!
//! The ducking test among them needs Windows set to lower other sounds
//! (the Sound window's Communications tab) and "CABLE Input" made the default
//! communications device, not the default device: Windows ducks only that
//! device's streams.
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

static MARKS: [AtomicU64; 9] = [const { AtomicU64::new(0) }; 9];

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

/// Publishes a flat picture of [shade] on [room] as [kind], until [stop] is
/// set.
async fn publish_flat(
    room: &Room,
    kind: TrackSource,
    codec: VideoCodec,
    shade: u8,
    stop: &Arc<AtomicBool>,
) {
    let track_name = if kind == TrackSource::Camera {
        "camera"
    } else {
        "screen_share"
    };
    let source = NativeVideoSource::new(
        VideoResolution {
            width: WIDTH,
            height: HEIGHT,
        },
        false,
    );
    let track =
        LocalVideoTrack::create_video_track(track_name, RtcVideoSource::Native(source.clone()));
    room.local_participant()
        .publish_track(
            LocalTrack::Video(track),
            TrackPublishOptions {
                source: kind,
                video_codec: codec,
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
    let stopping = stop.clone();
    tokio::task::spawn_blocking(move || {
        while !stopping.load(Ordering::SeqCst) {
            let mut buffer = I420Buffer::new(WIDTH, HEIGHT);
            let (y, u, v) = buffer.data_mut();
            y.fill(shade);
            u.fill(128);
            v.fill(128);
            source.capture_frame(&VideoFrame::new(VideoRotation::VideoRotation0, buffer));
            std::thread::sleep(Duration::from_millis(1000 / u64::from(FPS)));
        }
    });
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
        Share::start_in(server, room_name, identity, key, index, VideoCodec::VP8).await
    }

    /// H264 goes out the way a share sends it, from the GPU encoder, where
    /// this build has one: libwebrtc's own sent a flat picture no viewer
    /// received (Nov 2 2026), and no share is sent that way.
    async fn start_in(
        server: &Server,
        room_name: &str,
        identity: &str,
        key: &[u8],
        index: i32,
        codec: VideoCodec,
    ) -> Share {
        #[cfg(gpu_encoder)]
        if codec == VideoCodec::H264 {
            use crate::screenshare::encoder::SEND_H264_HIGH;
            return Share::start_gpu_h264(server, room_name, identity, key, index, SEND_H264_HIGH)
                .await;
        }
        let room = room::connect(
            &server.url,
            &server.token(room_name, identity, false),
            key,
            index,
        )
        .await
        .expect("sharer connects");
        let stop = Arc::new(AtomicBool::new(false));
        publish_flat(&room, TrackSource::Screenshare, codec, SHADE, &stop).await;
        Share { room, stop }
    }

    #[cfg(gpu_encoder)]
    async fn start_gpu_h264(
        server: &Server,
        room_name: &str,
        identity: &str,
        key: &[u8],
        index: i32,
        high: bool,
    ) -> Share {
        use crate::screenshare::encoder::{EncoderSettings, GpuCodec, GpuEncoder, Nv12Frame};
        use crate::screenshare::gpu_live_test::ToSource;
        use livekit::options::VideoEncoderBackend;
        let room = room::connect(
            &server.url,
            &server.token(room_name, identity, false),
            key,
            index,
        )
        .await
        .expect("sharer connects");
        let source = NativeVideoSource::new_encoded(VideoResolution {
            width: WIDTH,
            height: HEIGHT,
        });
        let encoder = GpuEncoder::open(
            EncoderSettings {
                codec: GpuCodec::H264,
                width: WIDTH,
                height: HEIGHT,
                fps: FPS,
                max_bitrate_bps: 2_000_000,
                start_bitrate_bps: 2_000_000,
                h264_high: high,
                gpu_capture: true,
            },
            Box::new(ToSource(source.clone())),
        )
        .expect("a hardware H264 encoder opens");
        let track =
            LocalVideoTrack::create_video_track("screen_share", RtcVideoSource::Native(source));
        room.local_participant()
            .publish_track(
                LocalTrack::Video(track),
                TrackPublishOptions {
                    source: TrackSource::Screenshare,
                    video_codec: VideoCodec::H264,
                    video_encoder: VideoEncoderBackend::PreEncoded,
                    h264_high: high,
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
            let len = Nv12Frame::len_for(WIDTH, HEIGHT);
            let luma = (WIDTH * HEIGHT) as usize;
            while !stopping.load(Ordering::SeqCst) {
                let mut data = encoder.buffer(len);
                data[..luma].fill(SHADE);
                data[luma..].fill(128);
                let timestamp_us = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_micros() as i64;
                encoder.submit(Nv12Frame { data, timestamp_us });
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

/// Waits until the watch connection is lost with a reason naming [why].
async fn lost_with(why: &str, within: Duration) -> bool {
    let until = Instant::now() + within;
    while Instant::now() < until {
        if session::lost_reasons().iter().any(|r| r.contains(why)) {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    false
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
    frames::rift_watch_frame_unlock(texture, 1);
    Some((planes.width, planes.height, shade))
}

/// The share's receive numbers, polled a second apart as the app's stats
/// card polls them: its size and codec, and as many pictures a second as it
/// sends once the two are worked into a rate by their timestamps, which
/// proves those are microseconds.
async fn assert_stats(identity: &str, codec: &str) {
    let a = session::stats(identity)
        .await
        .expect("stats for a watched share");
    tokio::time::sleep(Duration::from_secs(1)).await;
    let b = session::stats(identity)
        .await
        .expect("stats a second later");
    let seconds = (b.timestamp_us - a.timestamp_us) as f64 / 1e6;
    let fps = f64::from(b.frames_decoded - a.frames_decoded) / seconds;
    let kbps = (b.bytes_received - a.bytes_received) as f64 * 8.0 / seconds / 1000.0;
    log::info!(
        "watch test stats: {}x{} {} {fps:.1} fps {kbps:.0} kbps rtt {:?}",
        b.width,
        b.height,
        b.codec,
        b.rtt_ms
    );
    assert_eq!((b.width, b.height), (WIDTH, HEIGHT), "the size sent");
    assert!(b.codec.eq_ignore_ascii_case(codec), "{codec}: {}", b.codec);
    let sent = f64::from(FPS);
    assert!(
        (sent * 0.7..=sent * 1.3).contains(&fps),
        "{fps:.1} pictures a second, {FPS} sent"
    );
    assert!(kbps > 0.0, "bytes arriving");
    assert!(
        b.packets_received > a.packets_received,
        "packets counted, for the loss of each poll"
    );
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
    session::watch(share_identity.to_string(), TEXTURE, mark_address(), false)
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
    assert_stats(share_identity, "VP8").await;

    // Unwatched: no more marks.
    session::unwatch(share_identity).await;
    let after = marks(TEXTURE);
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(marks(TEXTURE), after, "nothing marks a texture let go");

    // Watched again, already published: subscribed straight away.
    session::watch(share_identity.to_string(), TEXTURE, mark_address(), false)
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
    session::watch("early~desk_share".into(), OLD, mark_address(), false)
        .await
        .unwrap();
    session::watch("late~desk_share".into(), NEW, mark_address(), false)
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

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server; see the module doc"]
async fn live_watch_takes_only_a_phones_share() {
    let _ = env_logger::builder().is_test(true).try_init();
    let server = Server::from_env();
    let name = room_name("phone");
    let key = shared_key();
    // A phone shares on the connection it talks on, its camera beside it.
    let phone_identity = "member~phone";
    const CAMERA_SHADE: u8 = 60;
    const TEXTURE: u64 = 4;

    let _voice = start_watching(&server, &name, key.clone(), KEY_INDEX).await;
    let phone = Share {
        room: room::connect(
            &server.url,
            &server.token(&name, phone_identity, false),
            &key,
            KEY_INDEX,
        )
        .await
        .expect("the phone connects"),
        stop: Arc::new(AtomicBool::new(false)),
    };
    publish_flat(
        &phone.room,
        TrackSource::Camera,
        VideoCodec::VP8,
        CAMERA_SHADE,
        &phone.stop,
    )
    .await;
    session::watch(phone_identity.to_string(), TEXTURE, mark_address(), false)
        .await
        .expect("watches");
    tokio::time::sleep(Duration::from_secs(3)).await;
    assert_eq!(marks(TEXTURE), 0, "the phone's camera is not its share");

    publish_flat(
        &phone.room,
        TrackSource::Screenshare,
        VideoCodec::VP8,
        SHADE,
        &phone.stop,
    )
    .await;
    assert!(
        marked(TEXTURE, 0, 30, Duration::from_secs(15)).await,
        "the phone's share is drawn ({} marks)",
        marks(TEXTURE)
    );
    tokio::time::sleep(Duration::from_secs(2)).await;
    let shade = drawn(TEXTURE)
        .map(|(_, _, shade)| shade)
        .unwrap_or_default();
    assert!(
        shade.abs_diff(SHADE) <= 4,
        "the share's picture, not the camera's: {shade}"
    );

    session::stop().await;
    phone.end().await;
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server; see the module doc"]
async fn live_watch_gives_up_on_a_share_it_cannot_read() {
    let _ = env_logger::builder().is_test(true).try_init();
    let server = Server::from_env();
    let name = room_name("unreadable");
    let old_key = shared_key();
    let new_key: Vec<u8> = old_key.iter().map(|b| b ^ 0x5a).collect();
    const TEXTURE: u64 = 5;

    // The share began before a rotation; the watch connection opened after
    // it, with the new key only.
    let share = Share::start(&server, &name, "early~desk_share", &old_key, KEY_INDEX).await;
    let _voice = start_watching(&server, &name, new_key, KEY_INDEX + 1).await;
    session::watch("early~desk_share".into(), TEXTURE, mark_address(), false)
        .await
        .unwrap();

    assert!(
        lost_with("no picture", Duration::from_secs(12)).await,
        "a share this connection cannot read goes back to the call: {:?}",
        session::lost_reasons()
    );
    assert_eq!(marks(TEXTURE), 0);

    session::stop().await;
    share.end().await;
}

/// Interleaved stereo for frame [index] of 10 ms: a 1 kHz tone in the left
/// ear for a second, then in the right.
#[cfg(any(target_os = "linux", windows))]
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

/// The test sink, checked: its name, as WebRTC lists it.
#[cfg(target_os = "linux")]
pub(super) fn test_output() -> String {
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
    output
}

/// VB-Cable's input, checked: its endpoint id, as WebRTC lists it.
#[cfg(windows)]
pub(super) fn test_output() -> String {
    let input = cable::endpoint(wasapi::Direction::Render, "CABLE Input");
    let name = input.get_friendlyname().unwrap_or_default();
    assert!(name.contains("CABLE"), "only into VB-Cable: {name}");
    let id = input.get_id().expect("an endpoint id");
    let default = wasapi::DeviceEnumerator::new()
        .and_then(|e| e.get_default_device(&wasapi::Direction::Render))
        .and_then(|d| d.get_id())
        .ok();
    assert_ne!(
        default.as_deref(),
        Some(id.as_str()),
        "VB-Cable is not the default output, which other sounds would play into"
    );
    id
}

/// A share sending [tone_frame]'s tone, watched through Rust at full volume
/// onto the test output, its picture arrived.
#[cfg(any(target_os = "linux", windows))]
struct ToneShare {
    _voice: Room,
    share: Share,
    feed: crate::sharing::audio::AudioCaptureHandle,
}

#[cfg(any(target_os = "linux", windows))]
impl ToneShare {
    const IDENTITY: &str = "member~desk_share";
    const TEXTURE: u64 = 0;

    async fn start(what: &str) -> ToneShare {
        use crate::sharing::audio::{publish_and_feed, Command, Pcm, SpawnCapture};
        let server = Server::from_env();
        let name = room_name(what);
        let key = shared_key();
        let voice = start_watching(&server, &name, key.clone(), KEY_INDEX).await;
        session::watch(
            Self::IDENTITY.to_string(),
            Self::TEXTURE,
            mark_address(),
            false,
        )
        .await
        .expect("watches");
        session::set_volume(Self::IDENTITY, 1.0).await;
        let share = Share::start(&server, &name, Self::IDENTITY, &key, KEY_INDEX).await;
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
            marked(
                Self::TEXTURE,
                marks(Self::TEXTURE),
                10,
                Duration::from_secs(15)
            )
            .await,
            "the picture arrives"
        );
        ToneShare {
            _voice: voice,
            share,
            feed,
        }
    }

    async fn end(self) {
        self.feed.terminate();
        session::stop().await;
        self.share.end().await;
    }
}

/// Logs when [what] begins, and adds it to [phases].
#[cfg(any(target_os = "linux", windows))]
fn begins(phases: &mut Vec<(&'static str, Instant)>, what: &'static str) {
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis();
    log::info!("sound test: {what} at {ms}");
    phases.push((what, Instant::now()));
}

#[cfg(any(target_os = "linux", windows))]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a test output; see the module doc"]
async fn live_watched_sound_plays_in_stereo_at_its_volume() {
    let _ = env_logger::builder().is_test(true).try_init();
    super::sound::set_output(Some(test_output()));
    #[cfg(windows)]
    let recording = cable::Recording::start();
    let tone = ToneShare::start("sound").await;
    let share_identity = ToneShare::IDENTITY;

    let mut phases = Vec::new();
    let mut at = |what: &'static str| begins(&mut phases, what);
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
    tokio::time::sleep(Duration::from_secs(2)).await;
    at("end");

    tone.end().await;
    #[cfg(windows)]
    cable::check(&recording.stop(), &phases);
    #[cfg(not(windows))]
    let _ = phases;
}

/// Windows turns other sounds down while a call's playback is open on the
/// communications device (`CALLS.md`, *Windows turning other apps down*). The
/// share's sound through the call is part of that playback; Rust's own stream
/// is not, so it might be turned down with everything else. Here a silent
/// stream opens on the communications device, as a call's playback does,
/// while the tone plays into VB-Cable: first in this process, as Rift's call
/// is beside Rust's player, where the tone must not drop by more than 1 dB;
/// then in another process, another app's call, which must turn the tone
/// down, or the first proves nothing. Needs Windows' choice to be anything
/// but "do nothing", which sends no duck at all.
#[cfg(windows)]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and VB-Cable; see the module doc"]
async fn live_watched_sound_is_not_turned_down_beside_a_call() {
    let _ = env_logger::builder().is_test(true).try_init();
    assert_ne!(
        crate::ducking::preference(),
        3,
        "Windows is set to do nothing beside a call, so nothing would be turned down: choose a reduction in the Sound window's Communications tab (control mmsys.cpl,,3) and run again"
    );
    crate::ducking::listen().expect("the duck listener");
    super::sound::set_output(Some(test_output()));
    let recording = cable::Recording::start();
    let tone = ToneShare::start("duck").await;

    let mut phases = Vec::new();
    begins(&mut phases, "alone");
    tokio::time::sleep(Duration::from_secs(3)).await;
    let ducks = crate::ducking::ducks();
    let call = cable::Call::open();
    begins(&mut phases, "beside its own call");
    tokio::time::sleep(Duration::from_secs(4)).await;
    let ducked = crate::ducking::ducks() > ducks;
    drop(call);
    begins(&mut phases, "between");
    tokio::time::sleep(Duration::from_secs(2)).await;
    let mut other = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--ignored",
            "--exact",
            "watching::live_test::another_apps_call_for_the_ducking_test",
        ])
        .env(ANOTHER_APPS_CALL, "5")
        .stdout(std::process::Stdio::null())
        .spawn()
        .expect("another process for the call");
    let ducks = crate::ducking::ducks();
    let until = Instant::now() + Duration::from_secs(10);
    while crate::ducking::ducks() == ducks && Instant::now() < until {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let other_ducked = crate::ducking::ducks() > ducks;
    begins(&mut phases, "beside another app's call");
    tokio::time::sleep(Duration::from_secs(2)).await;
    let _ = other.wait();
    begins(&mut phases, "after");
    tokio::time::sleep(Duration::from_secs(3)).await;
    begins(&mut phases, "end");
    tone.end().await;

    cable::check_beside_a_call(&recording.stop(), &phases, ducked, other_ducked);
}

/// How long [another_apps_call_for_the_ducking_test] holds its call, in
/// seconds; without it, that test does nothing.
#[cfg(windows)]
const ANOTHER_APPS_CALL: &str = "RIFT_DUCK_TEST_CALL_SECONDS";

/// The other process's call in the ducking test, which starts it.
#[cfg(windows)]
#[test]
#[ignore = "started by live_watched_sound_is_not_turned_down_beside_a_call"]
fn another_apps_call_for_the_ducking_test() {
    let Some(seconds) = std::env::var(ANOTHER_APPS_CALL)
        .ok()
        .and_then(|s| s.parse().ok())
    else {
        return;
    };
    let call = cable::Call::open();
    std::thread::sleep(Duration::from_secs(seconds));
    drop(call);
}

/// VB-Cable, for the sound test on Windows: what plays into "CABLE Input"
/// comes out of "CABLE Output", recorded here and measured.
#[cfg(windows)]
mod cable {
    use super::tone_frame;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::thread::JoinHandle;
    use std::time::{Duration, Instant};
    use wasapi::{DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat};

    /// The active endpoint whose name starts with `name`.
    pub(super) fn endpoint(direction: Direction, name: &str) -> wasapi::Device {
        let _ = wasapi::initialize_mta().ok();
        let collection = DeviceEnumerator::new()
            .and_then(|e| e.get_device_collection(&direction))
            .expect("the endpoints");
        (0..collection.get_nbr_devices().unwrap_or(0))
            .filter_map(|i| collection.get_device_at_index(i).ok())
            .find(|d| d.get_friendlyname().is_ok_and(|n| n.starts_with(name)))
            .unwrap_or_else(|| panic!("no {name}: is VB-Cable installed?"))
    }

    /// Each packet the cable's output gave, as it arrived: 48 kHz stereo.
    type Packets = Vec<(Instant, Vec<i16>)>;

    pub(super) struct Recording {
        stop: Arc<AtomicBool>,
        thread: JoinHandle<Packets>,
    }

    impl Recording {
        pub(super) fn start() -> Recording {
            let stop = Arc::new(AtomicBool::new(false));
            let stopped = stop.clone();
            let (started, opened) = std::sync::mpsc::channel();
            let thread = std::thread::spawn(move || {
                let device = endpoint(Direction::Capture, "CABLE Output");
                let mut client = device.get_iaudioclient().expect("a client");
                let format = WaveFormat::new(16, 16, &SampleType::Int, 48_000, 2, None);
                let mode = StreamMode::PollingShared {
                    autoconvert: true,
                    buffer_duration_hns: 10_000_000,
                };
                client
                    .initialize_client(&format, &Direction::Capture, &mode)
                    .expect("the cable records 48 kHz stereo");
                let capture = client.get_audiocaptureclient().expect("a capture client");
                client.start_stream().expect("recording starts");
                let _ = started.send(());
                let mut buffer = vec![0u8; 64 * 1024];
                let mut packets = Packets::new();
                while !stopped.load(Ordering::SeqCst) {
                    while let Ok((frames, info)) = capture.read_from_device(&mut buffer) {
                        if frames == 0 {
                            break;
                        }
                        let samples = if info.flags.silent {
                            vec![0; frames as usize * 2]
                        } else {
                            buffer[..frames as usize * 4]
                                .chunks_exact(2)
                                .map(|b| i16::from_le_bytes([b[0], b[1]]))
                                .collect()
                        };
                        packets.push((Instant::now(), samples));
                    }
                    std::thread::sleep(Duration::from_millis(5));
                }
                let _ = client.stop_stream();
                packets
            });
            opened.recv().expect("the recording opens");
            Recording { stop, thread }
        }

        pub(super) fn stop(self) -> Packets {
            self.stop.store(true, Ordering::SeqCst);
            self.thread.join().expect("the recording ends")
        }
    }

    /// The level of each channel, in dBFS, of each tenth of a second recorded
    /// between `from` and `to`.
    fn levels(packets: &Packets, from: Instant, to: Instant) -> Vec<(f64, f64)> {
        let samples: Vec<i16> = packets
            .iter()
            .filter(|(at, _)| *at >= from && *at <= to)
            .flat_map(|(_, samples)| samples.iter().copied())
            .collect();
        samples
            .chunks_exact(4800 * 2)
            .map(|block| {
                (
                    dbfs(block.iter().step_by(2)),
                    dbfs(block.iter().skip(1).step_by(2)),
                )
            })
            .collect()
    }

    fn dbfs<'a>(samples: impl Iterator<Item = &'a i16>) -> f64 {
        let (sum, count) = samples.fold((0.0, 0usize), |(sum, count), &s| {
            (sum + f64::from(s).powi(2), count + 1)
        });
        let rms = (sum / count.max(1) as f64).sqrt();
        20.0 * (rms.max(1e-9) / 32768.0).log10()
    }

    /// The blocks of the part named `name`, from half a second after it began
    /// to a fifth before the next, which leaves the output's hold and the
    /// server's turn out of it.
    fn part(packets: &Packets, phases: &[(&str, Instant)], name: &str) -> Vec<(f64, f64)> {
        let i = phases.iter().position(|(n, _)| *n == name).unwrap();
        let blocks = levels(
            packets,
            phases[i].1 + Duration::from_millis(500),
            phases[i + 1].1 - Duration::from_millis(200),
        );
        assert!(
            blocks.len() >= 3,
            "{name}: recorded ({} blocks)",
            blocks.len()
        );
        blocks
    }

    /// The loudest tenth of a second in the left, and in the right: the tone
    /// moves ears each second, so each part has both.
    fn loudest(blocks: &[(f64, f64)]) -> ((f64, f64), (f64, f64)) {
        let left = blocks.iter().copied().max_by(|a, b| a.0.total_cmp(&b.0));
        let right = blocks.iter().copied().max_by(|a, b| a.1.total_cmp(&b.1));
        (left.unwrap(), right.unwrap())
    }

    /// The quietest tenth of a second, both ears together: the tone is in
    /// one ear or the other, or half in each, so it is the same in every
    /// block until something turns it down.
    fn quietest_both(blocks: &[(f64, f64)]) -> f64 {
        blocks
            .iter()
            .map(|(l, r)| 10.0 * (10f64.powf(l / 10.0) + 10f64.powf(r / 10.0)).log10())
            .fold(f64::MAX, f64::min)
    }

    pub(super) fn check(packets: &Packets, phases: &[(&str, Instant)]) {
        let sent = dbfs(tone_frame(0).iter().step_by(2));
        let part = |name: &str| part(packets, phases, name);
        let quiet = |blocks: &[(f64, f64)]| {
            blocks
                .iter()
                .map(|(l, r)| l.max(*r))
                .fold(f64::MIN, f64::max)
        };

        let (left, right) = loudest(&part("full"));
        log::info!(
            "sound test: sent {sent:.1} dBFS; full: left {:.1} (right {:.1} then), right {:.1} (left {:.1} then)",
            left.0,
            left.1,
            right.1,
            right.0
        );
        assert!(
            (left.0 - sent).abs() <= 1.0,
            "left at the level sent: {:.1}",
            left.0
        );
        assert!(
            (right.1 - sent).abs() <= 1.0,
            "right at the level sent: {:.1}",
            right.1
        );
        assert!(
            left.1 < sent - 40.0,
            "nothing in the right while the left plays: {:.1}",
            left.1
        );
        assert!(
            right.0 < sent - 40.0,
            "nothing in the left while the right plays: {:.1}",
            right.0
        );

        let nothing = quiet(&part("nothing"));
        log::info!("sound test: nothing: loudest {nothing:.1} dBFS");
        assert!(nothing < -60.0, "silent at volume nothing: {nothing:.1}");

        let (left, right) = loudest(&part("half"));
        log::info!("sound test: half: left {:.1}, right {:.1}", left.0, right.1);
        let half = sent - 6.02;
        assert!(
            (left.0 - half).abs() <= 1.0,
            "6 dB down at half, left: {:.1}",
            left.0
        );
        assert!(
            (right.1 - half).abs() <= 1.0,
            "6 dB down at half, right: {:.1}",
            right.1
        );

        let unwatched = quiet(&part("unwatched"));
        log::info!("sound test: unwatched: loudest {unwatched:.1} dBFS");
        assert!(unwatched < -60.0, "silent once unwatched: {unwatched:.1}");
    }

    /// The tone beside this process's own call no more than 1 dB below the
    /// tone alone, and beside another app's turned down by more than 6 dB,
    /// or the first proves nothing.
    pub(super) fn check_beside_a_call(
        packets: &Packets,
        phases: &[(&str, Instant)],
        ducked: bool,
        other_ducked: bool,
    ) {
        let level = |name: &str| quietest_both(&part(packets, phases, name));
        let alone = level("alone");
        let own = level("beside its own call");
        let other = level("beside another app's call");
        let after = level("after");
        log::info!(
        "sound test: quietest alone {alone:.1} dBFS, beside its own call {own:.1} (Windows ducked: {ducked}), beside another app's {other:.1} (ducked: {other_ducked}), after {after:.1}"
        );
        assert!(
            ducked,
            "Windows turned nothing down for this process's call"
        );
        assert!(
            other_ducked && other < alone - 6.0,
        "another app's call did not turn the cable down ({other:.1} beside it, {alone:.1} alone), so the cable is out of Windows' reach and this proves nothing"
        );
        assert!(
            own >= alone - 1.0,
            "turned down beside its own call: {alone:.1} alone, {own:.1} beside it"
        );
        assert!(
            after >= alone - 1.0,
            "back up once the other call ended: {after:.1}"
        );
    }

    /// A call's playback as Windows sees one: a stream opened on the
    /// communications device through its role, playing silence until dropped.
    pub(super) struct Call {
        stop: Arc<AtomicBool>,
        thread: Option<JoinHandle<()>>,
    }

    impl Call {
        pub(super) fn open() -> Call {
            let stop = Arc::new(AtomicBool::new(false));
            let stopped = stop.clone();
            let (started, opened) = std::sync::mpsc::channel();
            let thread = std::thread::spawn(move || {
                let _ = wasapi::initialize_mta().ok();
                let device = DeviceEnumerator::new()
                    .and_then(|e| {
                        e.get_default_device_for_role(
                            &Direction::Render,
                            &wasapi::Role::Communications,
                        )
                    })
                    .expect("a communications device");
                log::info!(
                    "sound test: the call plays silence on {}",
                    device.get_friendlyname().unwrap_or_default()
                );
                let mut client = device.get_iaudioclient().expect("a client");
                let format = WaveFormat::new(16, 16, &SampleType::Int, 48_000, 2, None);
                let mode = StreamMode::PollingShared {
                    autoconvert: true,
                    buffer_duration_hns: 1_000_000,
                };
                client
                    .initialize_client(&format, &Direction::Render, &mode)
                    .expect("the call's stream opens");
                let render = client.get_audiorenderclient().expect("a render client");
                client.start_stream().expect("the call's stream starts");
                let _ = started.send(());
                while !stopped.load(Ordering::SeqCst) {
                    let frames = client.get_available_space_in_frames().unwrap_or(0) as usize;
                    if frames > 0 {
                        let _ = render.write_to_device(frames, &vec![0u8; frames * 4], None);
                    }
                    std::thread::sleep(Duration::from_millis(10));
                }
                let _ = client.stop_stream();
            });
            opened.recv().expect("the call's stream opens");
            Call {
                stop,
                thread: Some(thread),
            }
        }
    }

    impl Drop for Call {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::SeqCst);
            if let Some(thread) = self.thread.take() {
                let _ = thread.join();
            }
        }
    }
}

#[cfg(gpu_encoder)]
/// The picture waiting for [texture] when it was decoded on the GPU: its
/// size, and whether it is there to draw while it is lent: both its layers'
/// fds open, or, in CUDA's memory, the picture and the library's copy, or on
/// Windows a texture array holding its slice, at least the picture's size.
fn lent_from_the_gpu(texture: u64) -> Option<(u32, u32, bool)> {
    let mut planes = std::mem::MaybeUninit::<frames::WatchPlanes>::uninit();
    // SAFETY: a WatchPlanes this test owns.
    if unsafe { frames::rift_watch_frame_lock(texture, planes.as_mut_ptr()) } == 0 {
        return None;
    }
    // SAFETY: written, since lock answered 1.
    let planes = unsafe { planes.assume_init() };
    let open = match planes.kind {
        frames::ON_GPU => planes
            .fds
            .iter()
            .all(|fd| *fd >= 0 && std::fs::metadata(format!("/proc/self/fd/{fd}")).is_ok()),
        frames::IN_CUDA => {
            !planes.picture.is_null() && planes.copy_to_gl.is_some() && planes.gl_close.is_some()
        }
        #[cfg(windows)]
        frames::IN_D3D11 => super::decode::slice_holds(&planes),
        _ => false,
    };
    frames::rift_watch_frame_unlock(texture, 1);
    Some((planes.width, planes.height, open))
}

#[cfg(gpu_encoder)]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a GPU decoder; see the module doc"]
async fn live_gpu_watch_decodes_each_codec_on_the_gpu() {
    let _ = env_logger::builder().is_test(true).try_init();
    #[cfg(windows)]
    let runner = super::decode::RunnerDeviceInPlace::new();
    super::decode::choose();
    let device = super::decode::gpu().expect(
        "decoding on the GPU here: under Wayland on the GPU drawing the screen (Linux), \
         or on adapter 0 (Windows)",
    );
    log::info!("gpu watch test: decoding on {device}");
    let server = Server::from_env();
    let key = shared_key();
    let share_identity = "member~desk_share";

    // H264 in both profiles: a share sends High, and a sharer on an older
    // version sends constrained baseline.
    for (texture, codec, high) in [
        (5, VideoCodec::VP8, None),
        (6, VideoCodec::VP9, None),
        (7, VideoCodec::H264, Some(false)),
        (8, VideoCodec::H264, Some(true)),
    ] {
        let name = room_name(&format!("gpu-{}", codec.as_str()));
        let voice = start_watching(&server, &name, key.clone(), KEY_INDEX).await;
        session::watch(share_identity.to_string(), texture, mark_address(), true)
            .await
            .expect("watches");
        let share = match high {
            Some(high) => {
                Share::start_gpu_h264(&server, &name, share_identity, &key, KEY_INDEX, high).await
            }
            None => {
                Share::start_in(
                    &server,
                    &name,
                    share_identity,
                    &key,
                    KEY_INDEX,
                    codec.clone(),
                )
                .await
            }
        };

        // A codec the driver says it lacks (AMD has no VP8 decoder) must
        // fail in that named way, which sends the app back to the call's
        // connection; the others must decode.
        let ours = match codec {
            VideoCodec::VP8 => super::decode::Codec::Vp8,
            VideoCodec::VP9 => super::decode::Codec::Vp9,
            _ => super::decode::Codec::H264,
        };
        let has = device.decodes(ours);
        log::info!("gpu watch test: the driver decodes {ours:?}: {has:?}");
        if has == Some(false) {
            let why = format!("the GPU cannot decode this {ours:?}");
            assert!(
                lost_with(&why, Duration::from_secs(15)).await,
                "{codec:?}, which the driver lacks: the watch connection lost with {why:?}"
            );
            assert_eq!(marks(texture), 0, "{codec:?}: no picture drawn");
            session::unwatch(share_identity).await;
            session::stop().await;
            share.end().await;
            let _ = voice.close().await;
            continue;
        }

        assert!(
            marked(texture, 0, 10, Duration::from_secs(15)).await,
            "{codec:?} pictures reach the runner's slot"
        );
        // As many pictures as the share sends, near enough: none lost to the
        // decoder.
        let from = marks(texture);
        tokio::time::sleep(Duration::from_secs(3)).await;
        let got = marks(texture) - from;
        log::info!("gpu watch test: {codec:?}, high {high:?}, {got} pictures in 3 s");
        if let Some(high) = high {
            assert_eq!(
                crate::screenshare::gpu_live_test::SENT_PROFILE.load(Ordering::Relaxed),
                if high { 100 } else { 66 },
                "the SPS sent"
            );
        }
        assert!(
            got >= u64::from(FPS * 3) * 8 / 10,
            "{codec:?}: {got} pictures in 3 s at {FPS} a second"
        );
        let (width, height, open) = lent_from_the_gpu(texture)
            .or_else(|| {
                std::thread::sleep(Duration::from_millis(100));
                lent_from_the_gpu(texture)
            })
            .expect("a picture waiting");
        assert_eq!(
            (width, height),
            (WIDTH, HEIGHT),
            "{codec:?} at the size sent"
        );
        assert!(open, "{codec:?}: a GPU picture, there to draw while lent");
        assert_stats(share_identity, codec.as_str()).await;

        session::unwatch(share_identity).await;
        let after = marks(texture);
        tokio::time::sleep(Duration::from_secs(1)).await;
        assert_eq!(marks(texture), after, "nothing marks a texture let go");
        session::stop().await;
        share.end().await;
        let _ = voice.close().await;
    }
    // Every decoder closed and every picture let go has handed back its
    // reference to the runner's device.
    #[cfg(windows)]
    runner.assert_all_handed_back();
}
