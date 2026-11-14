//! The GPU encoder's H264 through a real room to real viewers: one with the
//! call's key sees the picture, one with no key or the wrong key sees nothing
//! of it. libwebrtc's own H264 encoder goes through the same rooms as a
//! control. Needs a LiveKit server (see
//! `live_test.rs`) and a hardware H264 encoder; no screen.
use super::encoder::test_hooks;
use super::encoder::{
    h264, Encoded, EncodedSink, EncoderSettings, GpuCodec, GpuEncoder, Nv12Frame,
};
use super::live_test::{shared_key, viewer_as, Server, KEY_INDEX};
use super::session;
use crate::api::screenshare::types::{
    self as share, ScreenShareConfig, ShareCursor, SharePriority, ShareQuality,
};
use futures_util::StreamExt;
use livekit::e2ee::key_provider::{KeyProvider, KeyProviderOptions};
use livekit::e2ee::{E2eeOptions, EncryptionType};
use livekit::options::{TrackPublishOptions, VideoCodec, VideoEncoderBackend, VideoEncoding};
use livekit::prelude::*;
use livekit::track::{LocalTrack, LocalVideoTrack, TrackSource};
use livekit::webrtc::prelude::{
    I420Buffer, RtcVideoSource, VideoBuffer, VideoFrame, VideoRotation,
};
use livekit::webrtc::video_frame::{EncodedFrameType, EncodedVideoCodec, EncodedVideoFrame};
use livekit::webrtc::video_source::native::NativeVideoSource;
use livekit::webrtc::video_source::VideoResolution;
use livekit::webrtc::video_stream::native::NativeVideoStream;
use std::sync::atomic::Ordering;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::time::timeout;

const WIDTH: u32 = 1280;
const HEIGHT: u32 = 720;
const FPS: u32 = 30;

/// The GPU encoder's H264 into a pre-encoded source, as a share sends it
/// (also what the watch test shares H264 with, `watching/live_test.rs`).
pub(crate) struct ToSource(pub(crate) NativeVideoSource);

/// The same for H265, which needs nothing rewritten but its start codes.
pub(crate) struct H265ToSource(pub(crate) NativeVideoSource);

/// Set by a test: a keyframe every so many pictures, as viewers joining ask
/// for them. 0 is only those WebRTC asks for.
pub(crate) static H265_KEY_EVERY: std::sync::atomic::AtomicU32 =
    std::sync::atomic::AtomicU32::new(0);
/// Pictures and keyframes sent so far.
pub(crate) static H265_SENT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
pub(crate) static H265_KEYS_SENT: std::sync::atomic::AtomicU32 =
    std::sync::atomic::AtomicU32::new(0);

impl EncodedSink for H265ToSource {
    fn deliver(&mut self, frame: Encoded<'_>) {
        H265_SENT.fetch_add(1, Ordering::Relaxed);
        if frame.keyframe {
            H265_KEYS_SENT.fetch_add(1, Ordering::Relaxed);
        }
        let rewritten = h264::with_long_start_codes(frame.payload);
        self.0.capture_encoded_frame(&EncodedVideoFrame {
            codec: EncodedVideoCodec::H265,
            payload: rewritten.as_deref().unwrap_or(frame.payload),
            timestamp_us: frame.timestamp_us,
            frame_type: if frame.keyframe {
                EncodedFrameType::Key
            } else {
                EncodedFrameType::Delta
            },
            resolution: self.0.video_resolution(),
            frame_metadata: None,
        });
    }

    fn keyframe_wanted(&mut self) -> bool {
        let every = H265_KEY_EVERY.load(Ordering::Relaxed);
        let due = every > 0 && H265_SENT.load(Ordering::Relaxed) % every == 0;
        self.0.take_keyframe_request() || due
    }

    fn bitrate_wanted(&mut self) -> Option<u64> {
        self.0
            .take_rate_control_request()
            .map(|request| u64::from(request.target_bitrate_bps))
    }
}

/// H264 keyframes an encrypted viewer could not have found the parameter sets
/// of ([`h264::idr_readable_when_encrypted`]).
static UNREADABLE_KEYFRAMES: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// The `profile_idc` of the last SPS the GPU encoder sent: 100 is High, 66
/// baseline.
pub(crate) static SENT_PROFILE: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);

impl EncodedSink for ToSource {
    fn deliver(&mut self, frame: Encoded<'_>) {
        let rewritten = h264::for_encryption(frame.payload);
        let payload = rewritten.as_deref().unwrap_or(frame.payload);
        if frame.keyframe && !h264::idr_readable_when_encrypted(payload) {
            UNREADABLE_KEYFRAMES.fetch_add(1, Ordering::Relaxed);
        }
        // The byte after the SPS's NAL header, past its start code.
        if let Some(&profile) = h264::nal_units(payload)
            .into_iter()
            .find(|&(kind, _)| kind == 7)
            .and_then(|(_, sps)| {
                sps.iter()
                    .position(|&b| b == 1)
                    .and_then(|at| sps.get(at + 2))
            })
        {
            SENT_PROFILE.store(profile, Ordering::Relaxed);
        }
        self.0.capture_encoded_frame(&EncodedVideoFrame {
            codec: EncodedVideoCodec::H264,
            payload,
            timestamp_us: frame.timestamp_us,
            frame_type: if frame.keyframe {
                EncodedFrameType::Key
            } else {
                EncodedFrameType::Delta
            },
            resolution: self.0.video_resolution(),
            frame_metadata: None,
        });
    }
    fn keyframe_wanted(&mut self) -> bool {
        self.0.take_keyframe_request()
    }
    fn bitrate_wanted(&mut self) -> Option<u64> {
        self.0
            .take_rate_control_request()
            .map(|r| r.target_bitrate_bps)
    }
}

/// A key that is not the call's.
fn wrong_key() -> Vec<u8> {
    shared_key().into_iter().rev().collect()
}

fn options(key: Option<Vec<u8>>) -> RoomOptions {
    let mut options = RoomOptions::default();
    if let Some(key) = key {
        let key_provider = KeyProvider::with_shared_key(KeyProviderOptions::default(), key.clone());
        key_provider.set_shared_key(key, KEY_INDEX);
        options.encryption = Some(E2eeOptions {
            encryption_type: EncryptionType::Gcm,
            key_provider,
        });
    }
    options
}

/// Frames a viewer decodes from 12 s of a picture: the GPU encoder's H264,
/// in High when `gpu` says so, or libwebrtc's own when that is `None`.
async fn decoded_frames(
    gpu: Option<bool>,
    sharer_key: Option<Vec<u8>>,
    viewer_key: Option<Vec<u8>>,
) -> Decoded {
    let server = Server::from_env();
    let room = format!(
        "rift-gpu-test-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis()
    );
    let (viewer, mut events) = Room::connect(
        &server.url,
        &server.token(&room, "viewer", true),
        options(viewer_key),
    )
    .await
    .expect("viewer connects");
    let (sharer, _) = Room::connect(
        &server.url,
        &server.token(&room, "sharer", false),
        options(sharer_key),
    )
    .await
    .expect("sharer connects");

    let resolution = VideoResolution {
        width: WIDTH,
        height: HEIGHT,
    };
    let source = if gpu.is_some() {
        NativeVideoSource::new_encoded(resolution)
    } else {
        NativeVideoSource::new(resolution, false)
    };
    let encoder = gpu.map(|h264_high| {
        GpuEncoder::open(
            EncoderSettings {
                codec: GpuCodec::H264,
                width: WIDTH,
                height: HEIGHT,
                fps: FPS,
                max_bitrate_bps: 4_000_000,
                start_bitrate_bps: 4_000_000,
                h264_high,
                gpu_capture: true,
            },
            Box::new(ToSource(source.clone())),
        )
        .expect("a hardware encoder opens")
    });
    let raw = source.clone();
    let track = LocalVideoTrack::create_video_track("screen_share", RtcVideoSource::Native(source));
    sharer
        .local_participant()
        .publish_track(
            LocalTrack::Video(track.clone()),
            TrackPublishOptions {
                source: TrackSource::Screenshare,
                video_codec: VideoCodec::H264,
                video_encoder: if gpu.is_some() {
                    VideoEncoderBackend::PreEncoded
                } else {
                    VideoEncoderBackend::Auto
                },
                h264_high: gpu == Some(true),
                simulcast: false,
                video_encoding: Some(VideoEncoding {
                    max_bitrate: 4_000_000,
                    max_framerate: f64::from(FPS),
                }),
                ..Default::default()
            },
        )
        .await
        .expect("publishes");

    let feeding = tokio::task::spawn_blocking(move || {
        for n in 0..(FPS * 12) {
            let shade = |i: usize| ((i % WIDTH as usize) as u32 / 4 + n * 3) as u8;
            let timestamp_us = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_micros() as i64;
            match &encoder {
                Some(gpu) => {
                    let mut data = gpu.buffer(Nv12Frame::len_for(WIDTH, HEIGHT));
                    for (i, byte) in data.iter_mut().enumerate() {
                        *byte = shade(i);
                    }
                    gpu.submit(Nv12Frame { data, timestamp_us });
                }
                None => {
                    let mut buffer = I420Buffer::new(WIDTH, HEIGHT);
                    let (y, u, v) = buffer.data_mut();
                    for plane in [y, u, v] {
                        for (i, byte) in plane.iter_mut().enumerate() {
                            *byte = shade(i);
                        }
                    }
                    raw.capture_frame(&VideoFrame::new(VideoRotation::VideoRotation0, buffer));
                }
            }
            std::thread::sleep(Duration::from_millis(1000 / u64::from(FPS)));
        }
    });

    let remote = timeout(Duration::from_secs(10), async {
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
    .expect("the viewer subscribes");
    let mut stream = NativeVideoStream::new(remote.rtc_track());
    let mut frames = Decoded::default();
    let _ = timeout(Duration::from_secs(8), async {
        while let Some(frame) = stream.next().await {
            frames.any += 1;
            if shows_the_gradient(&frame.buffer.to_i420()) {
                frames.recognisable += 1;
            }
        }
    })
    .await;
    // The H264 each side agreed to with the server, as its fmtp line says.
    frames.sent_fmtp = fmtp_of(track.get_stats().await.unwrap_or_default());
    frames.fmtp = fmtp_of(remote.get_stats().await.unwrap_or_default());
    let _ = feeding.await;
    sharer.close().await.unwrap();
    viewer.close().await.unwrap();
    frames
}

/// What a viewer decoded: any picture at all, and pictures that show what
/// was sent. A viewer without the key still decodes encrypted H264 into
/// something, because the NAL headers are left readable and the decoder
/// conceals the rest; only the second count says the content got out.
#[derive(Debug, Default)]
struct Decoded {
    any: usize,
    recognisable: usize,
    /// The fmtp lines of the codec the viewer and the sharer negotiated.
    fmtp: String,
    sent_fmtp: String,
}

/// The fmtp line of the codec a track's video stream uses.
fn fmtp_of(stats: Vec<livekit::webrtc::stats::RtcStats>) -> String {
    use livekit::webrtc::stats::RtcStats;
    let codec_id = stats.iter().find_map(|s| match s {
        RtcStats::InboundRtp(i) if i.stream.kind == "video" => Some(i.stream.codec_id.clone()),
        RtcStats::OutboundRtp(o) if o.stream.kind == "video" => Some(o.stream.codec_id.clone()),
        _ => None,
    });
    stats
        .into_iter()
        .find_map(|s| match s {
            RtcStats::Codec(c) if Some(&c.rtc.id) == codec_id.as_ref() => {
                Some(c.codec.sdp_fmtp_line)
            }
            _ => None,
        })
        .unwrap_or_default()
}

/// Whether a picture shows the sent pattern: luma rising by one every four
/// pixels across a row. Encrypted bytes decoded as if they were a picture
/// do not.
fn shows_the_gradient(picture: &I420Buffer) -> bool {
    let (y, _, _) = picture.data();
    let (stride, _, _) = picture.strides();
    let stride = stride as usize;
    let width = picture.width() as usize;
    let rows = [picture.height() as usize / 4, picture.height() as usize / 2];
    let (mut matching, mut total) = (0, 0);
    for row in rows {
        let line = &y[row * stride..row * stride + width];
        for x in (0..width - 8).step_by(8) {
            let step = (i16::from(line[x + 8]) - i16::from(line[x])).rem_euclid(256);
            total += 1;
            if (1..=3).contains(&step) {
                matching += 1;
            }
        }
    }
    matching * 10 >= total * 7
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a hardware H264 encoder"]
async fn live_gpu_h264_is_seen_with_the_key_and_by_nobody_else() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let only = std::env::var("GPU_LIVE_ONLY").ok();
    for (path, gpu) in [
        ("gpu", Some(true)),
        ("gpu baseline", Some(false)),
        ("software", None),
    ] {
        if only.as_deref().is_some_and(|o| o != path) {
            continue;
        }
        seen_with_the_key_and_by_nobody_else(path, gpu).await;
    }
}

/// For one way of encoding: a viewer with the call's key sees the picture,
/// and one without it or with the wrong key does not.
async fn seen_with_the_key_and_by_nobody_else(path: &str, gpu: Option<bool>) {
    {
        let key = Some(shared_key());
        let plain = decoded_frames(gpu, None, None).await;
        let with_key = decoded_frames(gpu, key.clone(), key.clone()).await;
        let without_key = decoded_frames(gpu, key.clone(), None).await;
        let wrong_key = decoded_frames(gpu, key, Some(wrong_key())).await;
        log::info!(
            "gpu live test: {path}: {plain:?} unencrypted, {with_key:?} with the key, \
             {without_key:?} without it, {wrong_key:?} with the wrong one"
        );
        assert!(plain.recognisable > 100, "{path}: {plain:?} unencrypted");
        assert!(
            with_key.recognisable > 100,
            "{path}: {with_key:?} with the key"
        );
        assert_eq!(without_key.recognisable, 0, "{path}: seen without the key");
        assert_eq!(wrong_key.recognisable, 0, "{path}: seen with the wrong key");
        assert_eq!(
            UNREADABLE_KEYFRAMES.load(Ordering::Relaxed),
            0,
            "{path}: keyframes encrypted viewers cannot find the parameter sets of"
        );
        if let Some(high) = gpu {
            let (profile, fmtp) = if high {
                (100, "profile-level-id=6400")
            } else {
                (66, "profile-level-id=42e01f")
            };
            assert_eq!(
                SENT_PROFILE.load(Ordering::Relaxed),
                profile,
                "{path}: the SPS"
            );
            // Only the sharer's: the server forwards High to a viewer whose
            // connection it did not offer under constrained baseline's name.
            for decoded in [&plain, &with_key] {
                assert!(decoded.sent_fmtp.contains(fmtp), "{path}: {decoded:?}");
            }
        }
    }
}

// ── A real share on the GPU path ──────────────────────────

/// The next picture track a viewer is given, after any it already had.
async fn next_video_track(
    events: &mut tokio::sync::mpsc::UnboundedReceiver<RoomEvent>,
) -> RemoteVideoTrack {
    timeout(Duration::from_secs(15), async {
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
    .expect("a picture track")
}

/// What a viewer makes of a track: how long the first picture took, the
/// size of the last, how many arrived in `count` and which decoder made them.
struct Watched {
    first: Duration,
    size: (u32, u32),
    frames: usize,
    decoder: String,
}

async fn watch(track: &RemoteVideoTrack, count: Duration) -> Watched {
    let started = Instant::now();
    let mut stream = NativeVideoStream::new(track.rtc_track());
    let first = timeout(Duration::from_secs(10), stream.next()).await;
    let first_at = started.elapsed();
    let (mut size, mut frames) = match first {
        Ok(Some(first)) => ((first.buffer.width(), first.buffer.height()), 1),
        _ => {
            log::warn!("gpu share: no picture in 10 s");
            ((0, 0), 0)
        }
    };
    let _ = timeout(if frames == 0 { Duration::ZERO } else { count }, async {
        while let Some(frame) = stream.next().await {
            frames += 1;
            size = (frame.buffer.width(), frame.buffer.height());
        }
    })
    .await;
    let inbound = track.get_stats().await.ok().and_then(|stats| {
        stats.into_iter().find_map(|s| match s {
            livekit::webrtc::stats::RtcStats::InboundRtp(i) if i.stream.kind == "video" => Some(i),
            _ => None,
        })
    });
    if let Some(i) = &inbound {
        log::info!(
            "gpu share: viewer received {} frames, decoded {}, {} keyframes, dropped {}, {} PLIs, {} packets, {} lost",
            i.inbound.frames_received,
            i.inbound.frames_decoded,
            i.inbound.key_frames_decoded,
            i.inbound.frames_dropped,
            i.inbound.pli_count,
            i.received.packets_received,
            i.received.packets_lost
        );
    }
    if let Some(o) = session::video_stats()
        .await
        .unwrap_or_default()
        .into_iter()
        .find_map(|s| match s {
            livekit::webrtc::stats::RtcStats::OutboundRtp(o) if o.stream.kind == "video" => Some(o),
            _ => None,
        })
    {
        log::info!(
            "gpu share: sender handed WebRTC {} frames in all, this track sent {}, {} keyframes, {} PLIs",
            super::gpu_feed::DELIVERED.load(Ordering::Relaxed),
            o.outbound.frames_sent,
            o.outbound.key_frames_encoded,
            o.outbound.pli_count
        );
    }
    let decoder = inbound
        .map(|i| i.inbound.decoder_implementation)
        .unwrap_or_default();
    Watched {
        first: first_at,
        size,
        frames,
        decoder,
    }
}

/// The encoder the share's picture is going through, as WebRTC reports it.
async fn share_encoder() -> String {
    session::video_stats()
        .await
        .unwrap_or_default()
        .into_iter()
        .find_map(|s| match s {
            livekit::webrtc::stats::RtcStats::OutboundRtp(o) if o.stream.kind == "video" => {
                Some(o.outbound.encoder_implementation)
            }
            _ => None,
        })
        .unwrap_or_default()
}

fn h264_share(server: &Server, room: &str) -> ScreenShareConfig {
    super::sources::list(true);
    ScreenShareConfig {
        gpu_capture: true,
        livekit_url: server.url.clone(),
        livekit_token: server.token(room, "sharer", false),
        resolution: 1080,
        fps: 30,
        bitrate: 8,
        share_audio: false,
        capture_full_screen: true,
        selected_video_source_index: Some(0),
        portal_choice: None,
        codec: share::VideoCodec::H264,
        priority: SharePriority::Smoothness,
        cursor: ShareCursor::Always,
        selected_audio_source_index: None,
        selected_audio_source_sink: None,
        selected_audio_source_pid: None,
        e2ee_key: shared_key(),
        e2ee_key_index: KEY_INDEX,
    }
}

/// Driven through the share itself: the GPU picture reaches an encrypted
/// viewer, a size change reopens the encoder, a viewer joining late is sent a
/// keyframe, an encoder that fails mid-share hands over to VP9 without the
/// share ending, and a share asked for H264 with no GPU to make it goes out
/// as VP9. Needs a display as well, with something moving on it: Windows sends
/// a still screen's picture seldom, and the test counts them (Nov 2 2026, 7 in
/// 3 s on an idle desktop).
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display and a hardware H264 encoder"]
async fn live_gpu_share_resizes_rejoins_and_falls_back() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = format!(
        "rift-gpu-share-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis()
    );
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    session::start(h264_share(&server, &room))
        .await
        .expect("share starts");

    let picture = next_video_track(&mut events).await;
    let seen = watch(&picture, Duration::from_secs(3)).await;
    let encoder = share_encoder().await;
    log::info!(
        "gpu share: {}x{}, {} frames in 3 s, decoder {}, encoder {encoder}",
        seen.size.0,
        seen.size.1,
        seen.frames,
        seen.decoder
    );
    assert_eq!(encoder, "LiveKit pre-encoded passthrough");
    assert!(seen.frames > 30, "{} frames", seen.frames);

    session::update(ShareQuality {
        resolution: 720,
        fps: 30,
        bitrate: 8,
        codec: share::VideoCodec::H264,
        share_audio: false,
    })
    .await
    .expect("the share changes size");
    // The same track, now at the new size: the GPU path re-encodes in place.
    let resized = watch(&picture, Duration::from_secs(3)).await;
    log::info!(
        "gpu share: resized to {}x{}, {} frames, encoder {}",
        resized.size.0,
        resized.size.1,
        resized.frames,
        share_encoder().await
    );
    assert_eq!(resized.size.1, 720.min(seen.size.1));

    let joined = Instant::now();
    let (late, mut late_events) = viewer_as(&server, &room, "late-viewer").await;
    let late_seen = watch(
        &next_video_track(&mut late_events).await,
        Duration::from_secs(1),
    )
    .await;
    log::info!(
        "gpu share: a viewer joining late had a picture {} ms after joining, {} ms after subscribing",
        joined.elapsed().as_millis() - 1000,
        late_seen.first.as_millis()
    );
    // Measured Oct 4 2026: 0.1 to 0.35 s mostly, once 3 s, while WebRTC's
    // frame dropper still acts on pre-encoded frames (LiveKit rust-sdks
    // PR #1459); 0.2 to 1.4 s with that change.
    assert!(late_seen.first < Duration::from_secs(4));
    late.close().await.unwrap();

    test_hooks::FAIL_AFTER.store(1, Ordering::Relaxed);
    let after_failure = watch(&next_video_track(&mut events).await, Duration::from_secs(3)).await;
    test_hooks::FAIL_AFTER.store(0, Ordering::Relaxed);
    let encoder = share_encoder().await;
    log::info!(
        "gpu share: after the encoder failed, {}x{}, {} frames, decoder {}, encoder {encoder}",
        after_failure.size.0,
        after_failure.size.1,
        after_failure.frames,
        after_failure.decoder
    );
    assert_eq!(encoder, "libvpx");
    assert!(after_failure.frames > 30);
    assert_eq!(session::stop().await.unwrap(), "Stopped successfully");

    test_hooks::NO_GPU.store(true, Ordering::Relaxed);
    let started = session::start(h264_share(&server, &room)).await;
    test_hooks::NO_GPU.store(false, Ordering::Relaxed);
    started.expect("a share with no GPU starts");
    let without_gpu = watch(&next_video_track(&mut events).await, Duration::from_secs(2)).await;
    let encoder = share_encoder().await;
    log::info!(
        "gpu share: with no GPU, {} frames, decoder {}, encoder {encoder}",
        without_gpu.frames,
        without_gpu.decoder
    );
    assert_eq!(encoder, "libvpx");
    assert_eq!(session::stop().await.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// Counts what the encoder makes.
struct Counting(
    std::sync::Arc<std::sync::atomic::AtomicU32>,
    Option<std::fs::File>,
);

impl EncodedSink for Counting {
    fn deliver(&mut self, frame: Encoded<'_>) {
        self.0.fetch_add(1, Ordering::Relaxed);
        if let Some(file) = &mut self.1 {
            use std::io::Write;
            file.write_all(frame.payload).expect("the dump is written");
        }
    }

    fn keyframe_wanted(&mut self) -> bool {
        false
    }

    fn bitrate_wanted(&mut self) -> Option<u64> {
        None
    }
}

/// One picture and then a still screen, at a rate above 60: the picture has to
/// come out without a second's wait. NVENC is asked to hold one back up there
/// (`ffmpeg.rs`, `delay_frames`), and what it holds comes out only when the
/// next goes in, so the encoder's thread sends it again (`worker.rs`). It kept
/// a lone picture past half a second before that (RTX 3070 Ti, Nov 11 2026).
/// `RIFT_TEST_FPS` names another rate, `RIFT_FFENC_ENCODER` the encoder.
#[test]
#[ignore = "needs a hardware H264 encoder"]
fn live_gpu_a_lone_picture_is_not_held() {
    let fps = std::env::var("RIFT_TEST_FPS")
        .ok()
        .and_then(|fps| fps.parse().ok())
        .unwrap_or(120);
    let made = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
    let encoder = GpuEncoder::open(
        EncoderSettings {
            codec: GpuCodec::H264,
            width: WIDTH,
            height: HEIGHT,
            fps,
            max_bitrate_bps: 4_000_000,
            start_bitrate_bps: 4_000_000,
            h264_high: true,
            gpu_capture: false,
        },
        Box::new(Counting(made.clone(), None)),
    )
    .expect("a GPU encoder opens");
    let mut data = encoder.buffer(Nv12Frame::len_for(WIDTH, HEIGHT));
    data.fill(128);
    let sent = Instant::now();
    encoder.submit(Nv12Frame {
        data,
        timestamp_us: 0,
    });
    while made.load(Ordering::Relaxed) == 0 && sent.elapsed() < Duration::from_millis(150) {
        std::thread::sleep(Duration::from_millis(2));
    }
    let waited = sent.elapsed();
    println!(
        "{} at {fps} fps: {} out after {waited:?}",
        encoder.name(),
        made.load(Ordering::Relaxed)
    );
    assert!(
        made.load(Ordering::Relaxed) >= 1,
        "{} kept a lone picture for {waited:?}",
        encoder.name()
    );
}

/// A Wayland share's PipeWire stream and the encoder this computer picks, with
/// each import the encoder refuses dropped from the stream as a share does.
/// Needs something moving on the screen (a test pattern playing), the portal
/// token `pw_stream`'s tests use, and, on a hybrid laptop where NVIDIA's GPU is
/// beside the one drawing, `GPU_NO_NVENC=1`. `RIFT_DUMP_H264` names a file to
/// write the stream to.
#[cfg(target_os = "linux")]
struct LiveStream {
    /// Held for the stream: closing the portal's session ends it.
    _session: super::portal::PortalSession,
    encoder: GpuEncoder,
    stream: std::sync::Arc<super::pw_stream::PwStream>,
    pictures: super::latest::Taker<super::pw_stream::PwPicture>,
    made: std::sync::Arc<std::sync::atomic::AtomicU32>,
    refused: std::sync::Arc<std::sync::atomic::AtomicU32>,
}

#[cfg(target_os = "linux")]
impl LiveStream {
    fn open() -> Self {
        use super::encoder::dmabuf_target;
        use super::latest;
        use super::pw_stream::tests::screen;
        use super::pw_stream::{PwBuffers, PwStream};
        use std::sync::atomic::AtomicU32;
        use std::sync::Arc;

        let session = screen();
        let made = Arc::new(AtomicU32::new(0));
        let dump = std::env::var_os("RIFT_DUMP_H264")
            .map(|path| std::fs::File::create(path).expect("the dump opens"));
        let target = dmabuf_target().expect("a GPU takes DMA-BUFs");
        let encoder = GpuEncoder::open(
            EncoderSettings {
                codec: GpuCodec::H264,
                width: WIDTH,
                height: HEIGHT,
                fps: 60,
                max_bitrate_bps: 8_000_000,
                start_bitrate_bps: 8_000_000,
                h264_high: false,
                gpu_capture: true,
            },
            Box::new(Counting(made.clone(), dump)),
        )
        .expect("a GPU encoder opens");
        assert!(
            encoder.takes_gpu_picture(),
            "{} takes no DMA-BUF (GPU_NO_NVENC=1 beside NVIDIA's GPU)",
            encoder.name()
        );
        let (put, pictures) = latest::channel();
        let stream = Arc::new(
            PwStream::open(
                &session,
                60,
                Some(&target.render_node),
                target.external_modifiers,
                PwBuffers::DmaBuf,
                move |picture| drop(put.put(picture)),
                Box::new(|event| log::info!("pipewire event: {event:?}")),
            )
            .expect("the stream opens"),
        );
        let refused = Arc::new(AtomicU32::new(0));
        {
            let stream = stream.clone();
            let refused = refused.clone();
            encoder.on_import_failed(Box::new(move |drm_format, modifier| {
                refused.fetch_add(1, Ordering::Relaxed);
                stream.drop_modifier(drm_format, modifier);
            }));
        }
        Self {
            _session: session,
            encoder,
            stream,
            pictures,
            made,
            refused,
        }
    }

    /// Sends what comes for `seconds`, each picture as the kind it arrived.
    /// Returns how many of each, DMA-BUFs first.
    fn run(&self, seconds: u64) -> (u32, u32) {
        use super::encoder::{DmaBufFrame, EncoderInput};

        let until = Instant::now() + Duration::from_secs(seconds);
        let (mut on_gpu, mut in_memory) = (0, 0);
        while Instant::now() < until {
            let picture = self
                .pictures
                .take_timeout(Duration::from_secs(2))
                .expect("no picture for 2 s; is something moving on the screen?");
            let timestamp_us = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_micros() as i64;
            if picture.memory().is_some() {
                self.encoder.submit_input(EncoderInput::Nv12(Nv12Frame {
                    data: gray_nv12_of(&picture),
                    timestamp_us,
                }));
                in_memory += 1;
            } else {
                self.encoder.submit_input(EncoderInput::DmaBuf(DmaBufFrame {
                    picture: std::sync::Arc::new(picture),
                    timestamp_us,
                }));
                on_gpu += 1;
            }
        }
        (on_gpu, in_memory)
    }

    /// Closes the stream and the encoder, and returns the frames made and the
    /// imports refused.
    fn finish(self) -> (u32, u32) {
        let Self {
            encoder,
            stream,
            made,
            refused,
            ..
        } = self;
        drop(stream);
        drop(encoder);
        (
            made.load(Ordering::Relaxed),
            refused.load(Ordering::Relaxed),
        )
    }
}

/// A memory picture as NV12 at the encoder's size, brightness only, enough for
/// `tear_check.py`'s test picture, which is all grays.
#[cfg(target_os = "linux")]
fn gray_nv12_of(picture: &super::pw_stream::PwPicture) -> Vec<u8> {
    let (data, stride, _) = picture.memory().expect("a memory picture");
    let size = picture.size();
    let (width, height) = (WIDTH as usize, HEIGHT as usize);
    let mut nv12 = vec![128; Nv12Frame::len_for(WIDTH, HEIGHT)];
    for row in 0..height {
        let from = &data[row * size.height as usize / height * stride as usize..];
        for column in 0..width {
            // In a gray, every channel holds the same, whichever comes first.
            let gray = from[column * size.width as usize / width * 4] as u32;
            nv12[row * width + column] = (16 + gray * 219 / 255) as u8;
        }
    }
    nv12
}

/// The settings switch keeps a share out of NVENC's GL side: with GPU capture
/// off the encoder takes no DMA-BUF, which is only true if it never opened EGL
/// and CUDA's interop, and the first look at the GPU leaves it out too.
#[cfg(target_os = "linux")]
#[test]
#[ignore = "needs NVIDIA drawing a Wayland screen"]
fn live_gpu_switch_keeps_nvenc_off_its_gl_side() {
    use super::encoder::dmabuf_target;
    use std::sync::atomic::AtomicU32;
    use std::sync::Arc;

    let open = |gpu_capture| {
        GpuEncoder::open(
            EncoderSettings {
                codec: GpuCodec::H264,
                width: 1280,
                height: 720,
                fps: 60,
                max_bitrate_bps: 8_000_000,
                start_bitrate_bps: 8_000_000,
                h264_high: false,
                gpu_capture,
            },
            Box::new(Counting(Arc::new(AtomicU32::new(0)), None)),
        )
        .expect("a GPU encoder opens")
    };
    assert!(!open(false).takes_gpu_picture(), "the switch is off");
    assert!(open(true).takes_gpu_picture(), "the switch is on");
    assert!(dmabuf_target().is_some_and(|target| target.external_modifiers));
}

/// The stream into the encoder, every picture staying on the GPU: a moving
/// screen at 60 fps is at least 50 frames a second. `RIFT_SHARE_SECONDS` says
/// how long to run in place of 3 s.
#[cfg(target_os = "linux")]
#[test]
#[ignore = "needs a Wayland screen with something moving and a GPU that takes DMA-BUFs"]
fn live_gpu_encodes_the_stream() {
    let seconds = std::env::var("RIFT_SHARE_SECONDS")
        .ok()
        .map_or(3, |seconds| seconds.parse().expect("a number of seconds"));
    let live = LiveStream::open();
    let (sent, _) = live.run(seconds);
    let (made, refused) = live.finish();
    log::info!("{sent} pictures in, {made} frames out, {refused} refused imports");
    assert!(
        made as u64 >= 50 * seconds,
        "{made} frames in {seconds} s from {sent} pictures"
    );
}

/// A share that moves to memory buffers and back, as one does when a feed that
/// cannot take DMA-BUFs comes and goes: the same encoder goes on from one kind
/// to the other with no gap. Play `tear_check.py play` and read the dump with it,
/// since a memory picture here is gray only.
#[cfg(target_os = "linux")]
#[test]
#[ignore = "needs a Wayland screen playing the tear picture and a GPU that takes DMA-BUFs"]
fn live_gpu_stream_moves_to_memory_and_back() {
    use super::pw_stream::PwBuffers;

    let live = LiveStream::open();
    let first = live.run(5);
    live.stream.set_buffers(PwBuffers::Memory);
    let middle = live.run(5);
    live.stream.set_buffers(PwBuffers::DmaBuf);
    let last = live.run(5);
    let (made, refused) = live.finish();
    log::info!("(GPU, memory) pictures {first:?} {middle:?} {last:?}, {made} frames out");
    assert_eq!(refused, 0, "imports refused");
    assert!(first.0 >= 200, "too few DMA-BUFs first: {first:?}");
    assert!(middle.1 >= 200, "too few memory pictures: {middle:?}");
    assert!(last.0 >= 200, "too few DMA-BUFs after: {last:?}");
    assert!(made >= 700, "only {made} frames in 15 s");
}

// ── Windows: Rift's own capture ──────────────────────────

/// A window of the test's own, as any app's: gray with a white bar that moves
/// a step every timer tick when `moving`, so a share of it has something new,
/// or drawn once and left still. In a process of its own (this test binary
/// again, running [`wgc_test_window`]), since libwebrtc leaves a process's own
/// windows out of its list. Closed as a person closes it when told to or
/// dropped.
#[cfg(target_os = "windows")]
mod test_window {
    use std::process::{Child, Command};
    use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
    use std::sync::OnceLock;
    use std::time::{Duration, Instant};
    use windows::core::{w, HSTRING};
    use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, RECT, WPARAM};
    use windows::Win32::Graphics::Gdi::{
        BeginPaint, EndPaint, FillRect, GetStockObject, InvalidateRect, GRAY_BRUSH, HBRUSH,
        PAINTSTRUCT, WHITE_BRUSH,
    };
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, FindWindowW,
        GetClientRect, GetMessageW, PostMessageW, PostQuitMessage, RegisterClassW, SetTimer,
        TranslateMessage, MSG, WINDOW_EX_STYLE, WM_APP, WM_CLOSE, WM_DESTROY, WM_PAINT, WM_TIMER,
        WNDCLASSW, WS_OVERLAPPEDWINDOW, WS_VISIBLE,
    };

    const CLASS: windows::core::PCWSTR = w!("RiftLiveTestWindow");
    /// Swap the window for a new one with the same title, as a game can.
    const WM_SWAP: u32 = WM_APP + 1;
    static MOVING: AtomicBool = AtomicBool::new(true);
    static STEP: AtomicI32 = AtomicI32::new(0);
    static TITLE: OnceLock<String> = OnceLock::new();
    /// The window being destroyed is one swapped out, which ends nothing.
    static SWAPPING: AtomicBool = AtomicBool::new(false);

    pub(super) struct TestWindow {
        hwnd: isize,
        title: HSTRING,
        child: Option<Child>,
    }

    impl TestWindow {
        pub(super) fn open(title: &str, moving: bool) -> Self {
            let mut command = Command::new(std::env::current_exe().unwrap());
            command
                .args([
                    "screenshare::gpu_live_test::wgc_test_window",
                    "--exact",
                    "--ignored",
                ])
                .env("RIFT_TEST_WINDOW", title);
            if !moving {
                command.env("RIFT_TEST_WINDOW_STILL", "1");
            }
            let child = command.spawn().expect("the test window's process starts");
            let title = HSTRING::from(title);
            let started = Instant::now();
            let hwnd = loop {
                // SAFETY: a lookup by class and title, nothing kept.
                if let Ok(hwnd) = unsafe { FindWindowW(CLASS, &title) } {
                    break hwnd;
                }
                assert!(
                    started.elapsed() < Duration::from_secs(10),
                    "the test window did not open"
                );
                std::thread::sleep(Duration::from_millis(50));
            };
            // Time for Windows to show it and list it.
            std::thread::sleep(Duration::from_millis(500));
            Self {
                hwnd: hwnd.0 as isize,
                title,
                child: Some(child),
            }
        }

        /// Swapped for a new window with the same title, the old one gone, as
        /// Red Dead Redemption 2 did mid-share. Returns once the new one is up.
        pub(super) fn swap(&mut self) {
            let old = self.hwnd;
            // SAFETY: a message to the test's own window.
            let _ =
                unsafe { PostMessageW(Some(HWND(old as *mut _)), WM_SWAP, WPARAM(0), LPARAM(0)) };
            let started = Instant::now();
            self.hwnd = loop {
                // SAFETY: a lookup by class and title, nothing kept.
                if let Ok(hwnd) = unsafe { FindWindowW(CLASS, &self.title) } {
                    if hwnd.0 as isize != old {
                        break hwnd.0 as isize;
                    }
                }
                assert!(
                    started.elapsed() < Duration::from_secs(5),
                    "the test window was not swapped"
                );
                std::thread::sleep(Duration::from_millis(10));
            };
        }

        /// Closed as a person closes it; gone once this returns.
        pub(super) fn close(mut self) {
            self.shut();
        }

        fn shut(&mut self) {
            let Some(mut child) = self.child.take() else {
                return;
            };
            // SAFETY: a message to the test's own window, which ends its loop.
            let _ = unsafe {
                PostMessageW(
                    Some(HWND(self.hwnd as *mut _)),
                    WM_CLOSE,
                    WPARAM(0),
                    LPARAM(0),
                )
            };
            let started = Instant::now();
            while child.try_wait().ok().flatten().is_none() {
                if started.elapsed() > Duration::from_secs(5) {
                    let _ = child.kill();
                    let _ = child.wait();
                    break;
                }
                std::thread::sleep(Duration::from_millis(20));
            }
        }
    }

    impl Drop for TestWindow {
        fn drop(&mut self) {
            self.shut();
        }
    }

    /// The window itself, on this thread, until it is closed.
    pub(super) fn run(title: &str, moving: bool) {
        MOVING.store(moving, Ordering::Relaxed);
        TITLE.set(title.to_string()).unwrap();
        // SAFETY: a window made, run and destroyed on this thread.
        unsafe {
            RegisterClassW(&WNDCLASSW {
                lpfnWndProc: Some(window_proc),
                hInstance: instance(),
                lpszClassName: CLASS,
                ..Default::default()
            });
            create();
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
    }

    fn instance() -> HINSTANCE {
        // SAFETY: this program's own module.
        HINSTANCE(unsafe { GetModuleHandleW(None) }.unwrap().0)
    }

    /// The window, titled [`TITLE`], on the calling thread, which runs its loop.
    fn create() -> HWND {
        // SAFETY: a window of a class registered by `run`, on its thread.
        unsafe {
            let hwnd = CreateWindowExW(
                WINDOW_EX_STYLE::default(),
                CLASS,
                &HSTRING::from(TITLE.get().unwrap().as_str()),
                WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                100,
                100,
                1280,
                720,
                None,
                None,
                Some(instance()),
                None,
            )
            .expect("the test window opens");
            SetTimer(Some(hwnd), 1, 16, None);
            hwnd
        }
    }

    unsafe extern "system" fn window_proc(
        hwnd: HWND,
        message: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        // SAFETY: called by Windows on the window's own thread, with its own handle.
        unsafe {
            match message {
                WM_SWAP => {
                    create();
                    SWAPPING.store(true, Ordering::Relaxed);
                    let _ = DestroyWindow(hwnd);
                    LRESULT(0)
                }
                WM_TIMER => {
                    if MOVING.load(Ordering::Relaxed) {
                        STEP.fetch_add(1, Ordering::Relaxed);
                        let _ = InvalidateRect(Some(hwnd), None, false);
                    }
                    LRESULT(0)
                }
                WM_PAINT => {
                    let mut paint = PAINTSTRUCT::default();
                    let dc = BeginPaint(hwnd, &mut paint);
                    let mut area = RECT::default();
                    let _ = GetClientRect(hwnd, &mut area);
                    FillRect(dc, &area, HBRUSH(GetStockObject(GRAY_BRUSH).0));
                    let width = (area.right - 40).max(1);
                    let x = (STEP.load(Ordering::Relaxed) * 8) % width;
                    let bar = RECT {
                        left: x,
                        top: 0,
                        right: x + 40,
                        bottom: area.bottom,
                    };
                    FillRect(dc, &bar, HBRUSH(GetStockObject(WHITE_BRUSH).0));
                    let _ = EndPaint(hwnd, &paint);
                    LRESULT(0)
                }
                WM_DESTROY => {
                    if !SWAPPING.swap(false, Ordering::Relaxed) {
                        PostQuitMessage(0);
                    }
                    LRESULT(0)
                }
                _ => DefWindowProcW(hwnd, message, wparam, lparam),
            }
        }
    }
}

/// Not a test of its own: the window [`test_window::TestWindow`] opens, run
/// in a process of its own by the tests that share it.
#[cfg(target_os = "windows")]
#[test]
#[ignore = "the Windows live tests' window, started by them"]
fn wgc_test_window() {
    let Ok(title) = std::env::var("RIFT_TEST_WINDOW") else {
        return;
    };
    test_window::run(&title, std::env::var_os("RIFT_TEST_WINDOW_STILL").is_none());
}

/// An H264 share of the test's own window, found by its title as the app's
/// list would show it.
#[cfg(target_os = "windows")]
fn window_share(server: &Server, room: &str, title: &str) -> ScreenShareConfig {
    let mut config = h264_share(server, room);
    let index = super::sources::list(false)
        .into_iter()
        .find(|source| source.title.contains(title))
        .unwrap_or_else(|| panic!("no window titled {title:?}"))
        .index;
    config.capture_full_screen = false;
    config.selected_video_source_index = Some(index);
    config
}

#[cfg(target_os = "windows")]
fn live_room(name: &str) -> String {
    format!(
        "rift-{name}-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis()
    )
}

/// The settings switch keeps a share entirely out of Rift's own capture: on,
/// the share opens one device and runs on Rift's session; off, it opens
/// neither and still shows the window.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display and a hardware H264 encoder that takes textures"]
async fn live_wgc_switch_keeps_the_share_off_the_gpu() {
    use super::capture_wgc::counts;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = live_room("wgc-switch");
    let title = "rift live test: the switch";
    let _window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    for gpu_capture in [true, false] {
        let devices = counts::DEVICES.load(Ordering::Relaxed);
        let sessions = counts::SESSIONS.load(Ordering::Relaxed);
        let mut config = window_share(&server, &room, title);
        config.gpu_capture = gpu_capture;
        session::start(config).await.expect("share starts");
        let seen = watch(&next_video_track(&mut events).await, Duration::from_secs(3)).await;
        let opened = (
            counts::DEVICES.load(Ordering::Relaxed) - devices,
            counts::SESSIONS.load(Ordering::Relaxed) - sessions,
        );
        log::info!(
            "wgc share, switch {}: {} frames in 3 s, {} devices and {} of Rift's sessions opened",
            if gpu_capture { "on" } else { "off" },
            seen.frames,
            opened.0,
            opened.1
        );
        assert!(seen.frames > 60, "{} frames", seen.frames);
        assert_eq!(opened, if gpu_capture { (1, 1) } else { (0, 0) });
        assert_eq!(session::stop().await.unwrap(), "Stopped successfully");
    }
    viewer.close().await.unwrap();
}

/// An H265 share moved to VP9 leaves Rift's capture for libwebrtc's, since VP9
/// reads its pictures from memory, and moved back to H265 comes back to Rift's
/// session on the same device, its new encoder taking the GPU's pictures again:
/// what FFmpeg's AMF logs as "AMF via D3D11." once more. Before, the share stayed
/// on libwebrtc's capturer and its encoder read memory to the end, and the rate
/// gate left out about one picture in seven (Nov 8 2026, `STEP4_AMD_WINDOWS.md`).
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display and a hardware H265 encoder that takes textures"]
async fn live_wgc_share_comes_back_from_vp9() {
    use super::capture_wgc::counts;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = live_room("wgc-back");
    let title = "rift live test: back from VP9";
    // As an app whose watched shares decode on the GPU: only that offers H265.
    crate::watching::decode::choose();
    crate::watching::decode::gpu().expect("decoding on the GPU here");
    let _window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    let devices = counts::DEVICES.load(Ordering::Relaxed);
    let sessions = counts::SESSIONS.load(Ordering::Relaxed);
    let feeds = counts::TEXTURE_FEEDS.load(Ordering::Relaxed);
    let mut config = window_share(&server, &room, title);
    config.codec = share::VideoCodec::H265;
    session::start(config).await.expect("share starts");
    let seen = watch(&next_video_track(&mut events).await, Duration::from_secs(2)).await;
    assert!(seen.frames > 30, "H265: {} frames", seen.frames);
    for codec in [share::VideoCodec::VP9, share::VideoCodec::H265] {
        session::update(ShareQuality {
            resolution: 1080,
            fps: 30,
            bitrate: 8,
            codec,
            share_audio: false,
        })
        .await
        .expect("the share changes codec");
        let seen = watch(&next_video_track(&mut events).await, Duration::from_secs(2)).await;
        log::info!(
            "wgc share, moved to {codec:?}: {} frames in 2 s, decoder {}",
            seen.frames,
            seen.decoder
        );
        assert!(seen.frames > 30, "{codec:?}: {} frames", seen.frames);
    }
    let opened = (
        counts::DEVICES.load(Ordering::Relaxed) - devices,
        counts::SESSIONS.load(Ordering::Relaxed) - sessions,
        counts::TEXTURE_FEEDS.load(Ordering::Relaxed) - feeds,
    );
    log::info!(
        "wgc share, H265 to VP9 and back: {} devices, {} of Rift's sessions, {} encoders on the GPU's pictures",
        opened.0,
        opened.1,
        opened.2
    );
    assert_eq!(
        opened,
        (1, 2, 2),
        "devices, sessions, encoders on the GPU's pictures"
    );
    assert_eq!(session::stop().await.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// A shared window closed mid-share, five times: each time the capture hears
/// it within 3 s and ends the share, and the stop the app then sends returns
/// at once.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display and a hardware H264 encoder that takes textures"]
async fn live_wgc_window_share_ends_when_the_window_closes() {
    use super::capture_wgc::counts;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = live_room("wgc-close");
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    for round in 1..=5 {
        let title = format!("rift live test: closing {round}");
        let window = test_window::TestWindow::open(&title, true);
        let sessions = counts::SESSIONS.load(Ordering::Relaxed);
        let closed = counts::CLOSED.load(Ordering::Relaxed);
        session::start(window_share(&server, &room, &title))
            .await
            .expect("share starts");
        let seen = watch(&next_video_track(&mut events).await, Duration::from_secs(2)).await;
        assert!(seen.frames > 30, "round {round}: {} frames", seen.frames);
        assert_eq!(
            counts::SESSIONS.load(Ordering::Relaxed),
            sessions + 1,
            "round {round}: not on Rift's capture"
        );
        let closing = Instant::now();
        window.close();
        let heard = timeout(Duration::from_secs(3), async {
            while counts::CLOSED.load(Ordering::Relaxed) == closed {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await;
        assert!(heard.is_ok(), "round {round}: the close was not heard");
        let heard_after = closing.elapsed();
        // What the app does when it hears the share ended.
        let stopping = Instant::now();
        let stopped = timeout(Duration::from_secs(5), session::stop())
            .await
            .unwrap_or_else(|_| panic!("round {round}: stop hung"));
        log::info!(
            "wgc share, round {round}: {} frames, the close heard in {} ms, stopped in {} ms",
            seen.frames,
            heard_after.as_millis(),
            stopping.elapsed().as_millis()
        );
        assert_eq!(stopped.unwrap(), "Stopped successfully");
    }
    viewer.close().await.unwrap();
}

/// A window that never changes, shared with nobody watching for long enough
/// that the stream pauses: a viewer joining then still gets its picture.
/// Windows sends nothing for a still window, so this is the repeat's work.
/// However quiet it is, it is never handed to libwebrtc's capturer.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display and a hardware H264 encoder that takes textures"]
async fn live_wgc_still_window_reaches_a_late_viewer() {
    use super::capture_wgc::counts;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = live_room("wgc-still");
    let title = "rift live test: still";
    let _window = test_window::TestWindow::open(title, false);
    let sessions = counts::SESSIONS.load(Ordering::Relaxed);
    let reopens = counts::REOPENS.load(Ordering::Relaxed);
    let handovers = counts::HANDOVERS.load(Ordering::Relaxed);
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    tokio::time::sleep(Duration::from_secs(8)).await;
    assert_eq!(
        counts::SESSIONS.load(Ordering::Relaxed),
        sessions + 1,
        "not on Rift's capture"
    );
    // How many depends on the desktop: Windows also sends a still window's
    // picture as the screen around it is drawn, 20 a second here (Nov 2 2026).
    log::info!(
        "wgc share, still window: {} new sessions in 8 s",
        counts::REOPENS.load(Ordering::Relaxed) - reopens
    );
    assert_eq!(
        counts::HANDOVERS.load(Ordering::Relaxed),
        handovers,
        "a still window was handed over"
    );
    let (late, mut events) = viewer_as(&server, &room, "late-viewer").await;
    let seen = watch(&next_video_track(&mut events).await, Duration::from_secs(2)).await;
    log::info!(
        "wgc share, still window: a late viewer's first picture {} ms after subscribing, {} in 2 s, {}x{}",
        seen.first.as_millis(),
        seen.frames,
        seen.size.0,
        seen.size.1
    );
    assert!(seen.frames >= 1, "no picture");
    assert!(seen.first < Duration::from_secs(1), "{:?}", seen.first);
    assert_eq!(session::stop().await.unwrap(), "Stopped successfully");
    late.close().await.unwrap();
}

/// A session Windows stops giving pictures from, as a driver reset left one
/// (Nov 2 2026): run with `RIFT_WGC_SILENT_AFTER=60`, which drops every picture
/// after the 60th of the process, a new session's too. The capture opens new
/// sessions once the source has been quiet, then hands the share to libwebrtc's
/// capturer when they all give nothing, and the viewer sees the window move
/// again on the same track.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display, a hardware H264 encoder that takes textures and RIFT_WGC_SILENT_AFTER"]
async fn live_wgc_silent_session_moves_to_libwebrtc() {
    use super::capture_wgc::counts;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    std::env::var("RIFT_WGC_SILENT_AFTER").expect("run with RIFT_WGC_SILENT_AFTER=60");
    assert!(
        std::env::var("RIFT_WGC_SILENT_FOR").is_err(),
        "run without RIFT_WGC_SILENT_FOR"
    );
    let server = Server::from_env();
    let room = live_room("wgc-silent");
    let title = "rift live test: silent";
    let _window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    let reopens = counts::REOPENS.load(Ordering::Relaxed);
    let handovers = counts::HANDOVERS.load(Ordering::Relaxed);
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    let track = next_video_track(&mut events).await;
    let before = watch(&track, Duration::from_secs(1)).await;
    let silent = Instant::now();
    let handed = timeout(Duration::from_secs(20), async {
        while counts::HANDOVERS.load(Ordering::Relaxed) == handovers {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
    let handed_after = silent.elapsed();
    assert!(handed.is_ok(), "never handed to libwebrtc's capturer");
    let after = watch(&track, Duration::from_secs(3)).await;
    log::info!(
        "wgc share, silent session: {} frames before, {} new sessions, handed over {} ms \
         after the watching, {} frames in 3 s after",
        before.frames,
        counts::REOPENS.load(Ordering::Relaxed) - reopens,
        handed_after.as_millis(),
        after.frames
    );
    assert!(
        counts::REOPENS.load(Ordering::Relaxed) > reopens,
        "no new session"
    );
    assert!(after.frames > 30, "{} frames after", after.frames);
    let stopped = timeout(Duration::from_secs(5), session::stop())
        .await
        .expect("stop hung");
    assert_eq!(stopped.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// A session that gives nothing for a while and then pictures again, as once a
/// driver reset has settled: run with `RIFT_WGC_SILENT_AFTER=60` and
/// `RIFT_WGC_SILENT_FOR=5000`. A later new session gives the pictures, the
/// share stays on Rift's session, and the viewer sees the window move again.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display, a hardware H264 encoder that takes textures, RIFT_WGC_SILENT_AFTER and RIFT_WGC_SILENT_FOR"]
async fn live_wgc_session_back_after_a_silence() {
    use super::capture_wgc::counts;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    std::env::var("RIFT_WGC_SILENT_AFTER").expect("run with RIFT_WGC_SILENT_AFTER=60");
    std::env::var("RIFT_WGC_SILENT_FOR").expect("run with RIFT_WGC_SILENT_FOR=5000");
    let server = Server::from_env();
    let room = live_room("wgc-back");
    let title = "rift live test: back";
    let _window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    let reopens = counts::REOPENS.load(Ordering::Relaxed);
    let back = counts::BACK.load(Ordering::Relaxed);
    let handovers = counts::HANDOVERS.load(Ordering::Relaxed);
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    let track = next_video_track(&mut events).await;
    let before = watch(&track, Duration::from_secs(1)).await;
    let silent = Instant::now();
    let came = timeout(Duration::from_secs(15), async {
        while counts::BACK.load(Ordering::Relaxed) == back {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
    let came_after = silent.elapsed();
    assert!(came.is_ok(), "no new session gave pictures again");
    let after = watch(&track, Duration::from_secs(3)).await;
    log::info!(
        "wgc share, session back: {} frames before, {} new sessions, back {} ms after the \
         watching, {} frames in 3 s after",
        before.frames,
        counts::REOPENS.load(Ordering::Relaxed) - reopens,
        came_after.as_millis(),
        after.frames
    );
    assert_eq!(
        counts::HANDOVERS.load(Ordering::Relaxed),
        handovers,
        "handed to libwebrtc's capturer"
    );
    assert!(after.frames > 30, "{} frames after", after.frames);
    let stopped = timeout(Duration::from_secs(5), session::stop())
        .await
        .expect("stop hung");
    assert_eq!(stopped.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// A GPU that stops drawing mid-share, as one being reset would: run with
/// `RIFT_D3D11_FAIL_AFTER=90`, which fails every picture after the 90th in the
/// converter. The last picture goes out again while the failure might be
/// passing, then the share moves to VP9 and the viewer is given that picture,
/// and the stop afterwards returns.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display, a hardware H264 encoder that takes textures and RIFT_D3D11_FAIL_AFTER"]
async fn live_wgc_failing_gpu_moves_to_vp9() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    std::env::var("RIFT_D3D11_FAIL_AFTER").expect("run with RIFT_D3D11_FAIL_AFTER=90");
    let server = Server::from_env();
    let room = live_room("wgc-fail");
    let title = "rift live test: failing";
    let _window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    let before = watch(&next_video_track(&mut events).await, Duration::from_secs(2)).await;
    assert_eq!(share_encoder().await, "LiveKit pre-encoded passthrough");
    assert!(before.frames > 30, "{} frames before", before.frames);
    let failing = Instant::now();
    let moved = timeout(Duration::from_secs(15), next_video_track(&mut events))
        .await
        .expect("the share moved to VP9");
    let moved_after = failing.elapsed();
    let after = watch(&moved, Duration::from_secs(3)).await;
    let encoder = share_encoder().await;
    log::info!(
        "wgc share, failing GPU: {} frames before, VP9's picture {} ms after the 2 s of watching, \
         {} frames in 3 s after, encoder {encoder}",
        before.frames,
        moved_after.as_millis(),
        after.frames
    );
    assert_eq!(encoder, "libvpx");
    assert!(after.frames > 30, "{} frames after", after.frames);
    // The failure starts about a second after the watching (the 90th picture,
    // at 30 a second), lasts a second (d3d11_nv12.c), then VP9 is published.
    assert!(
        moved_after < Duration::from_secs(4),
        "VP9 after {moved_after:?}"
    );
    let stopped = timeout(Duration::from_secs(5), session::stop())
        .await
        .expect("stop hung");
    assert_eq!(stopped.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// A game swapping its window mid-share, whose new window is refused its first
/// session (`hooks::REFUSE_WINDOWS`), as one only just opened may be: the share
/// looks again and goes on with the new window, on Rift's session.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display and a hardware H264 encoder that takes textures"]
async fn live_wgc_swapped_window_refused_once_is_followed() {
    use super::capture_wgc::{counts, hooks};
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = live_room("wgc-refused");
    let title = "rift live test: refused";
    let mut window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    let track = next_video_track(&mut events).await;
    let before = watch(&track, Duration::from_secs(1)).await;
    let closed = counts::CLOSED.load(Ordering::Relaxed);
    let handovers = counts::HANDOVERS.load(Ordering::Relaxed);
    hooks::REFUSE_WINDOWS.store(1, Ordering::Relaxed);
    window.swap();
    // A second or so to find the new window twice, then the bar moving again.
    let after = watch(&track, Duration::from_secs(4)).await;
    log::info!(
        "wgc share, a swapped window refused once: {} frames before, {} in the 4 s after",
        before.frames,
        after.frames
    );
    assert_eq!(
        hooks::REFUSE_WINDOWS.load(Ordering::Relaxed),
        0,
        "the new window was never refused"
    );
    assert!(after.frames > 60, "{} frames after", after.frames);
    assert_eq!(
        counts::CLOSED.load(Ordering::Relaxed),
        closed,
        "the share ended"
    );
    assert_eq!(
        counts::HANDOVERS.load(Ordering::Relaxed),
        handovers,
        "handed to libwebrtc's capturer"
    );
    let stopped = timeout(Duration::from_secs(5), session::stop())
        .await
        .expect("stop hung");
    assert_eq!(stopped.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// A game swapping its window, and the share then moving off Rift's capture:
/// run with `RIFT_D3D11_FAIL_AFTER=240`, which fails the converter some seconds
/// after the swap. Libwebrtc's capturer goes on with the window followed to, not
/// the one picked, which is gone, and the viewer sees it on VP9.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display, a hardware H264 encoder that takes textures and RIFT_D3D11_FAIL_AFTER"]
async fn live_wgc_swapped_window_moves_to_vp9() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    std::env::var("RIFT_D3D11_FAIL_AFTER").expect("run with RIFT_D3D11_FAIL_AFTER=240");
    let server = Server::from_env();
    let room = live_room("wgc-swap-vp9");
    let title = "rift live test: swapped";
    let mut window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    let track = next_video_track(&mut events).await;
    let before = watch(&track, Duration::from_secs(1)).await;
    window.swap();
    let followed = watch(&track, Duration::from_secs(2)).await;
    let moved = timeout(Duration::from_secs(15), next_video_track(&mut events))
        .await
        .expect("the share moved to VP9");
    let after = watch(&moved, Duration::from_secs(3)).await;
    let encoder = share_encoder().await;
    log::info!(
        "wgc share, swapped then VP9: {} frames before, {} in 2 s after the swap, {} in 3 s \
         on VP9, encoder {encoder}",
        before.frames,
        followed.frames,
        after.frames
    );
    assert!(
        followed.frames > 30,
        "{} frames after the swap",
        followed.frames
    );
    assert_eq!(encoder, "libvpx");
    // The bar moving at the share's 30 fps: VP9 repeating its last picture
    // makes about 10 a second.
    assert!(after.frames > 60, "{} frames on VP9", after.frames);
    let stopped = timeout(Duration::from_secs(5), session::stop())
        .await
        .expect("stop hung");
    assert_eq!(stopped.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// An encoder that fails while Windows gives no new picture, as on a GPU that is
/// gone: run with `RIFT_WGC_SILENT_AFTER=60`. Once the source is quiet, the
/// encoder's repeat of the last picture fails (`FAIL_REPEAT`), and the share
/// moves to VP9 at once, not after the new sessions' 12 s.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display, a hardware H264 encoder that takes textures and RIFT_WGC_SILENT_AFTER"]
async fn live_wgc_encoder_failing_on_a_still_picture_moves_to_vp9() {
    use super::capture_wgc::counts;
    use super::encoder::test_hooks;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    std::env::var("RIFT_WGC_SILENT_AFTER").expect("run with RIFT_WGC_SILENT_AFTER=60");
    assert!(
        std::env::var("RIFT_WGC_SILENT_FOR").is_err(),
        "run without RIFT_WGC_SILENT_FOR"
    );
    let server = Server::from_env();
    let room = live_room("wgc-still-fail");
    let title = "rift live test: still failing";
    let _window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    let reopens = counts::REOPENS.load(Ordering::Relaxed);
    let handovers = counts::HANDOVERS.load(Ordering::Relaxed);
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    next_video_track(&mut events).await;
    // Quiet for 2 s: the first new session.
    timeout(Duration::from_secs(10), async {
        while counts::REOPENS.load(Ordering::Relaxed) == reopens {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("the source never went quiet");
    test_hooks::FAIL_REPEAT.store(true, Ordering::Relaxed);
    let failing = Instant::now();
    let moved = timeout(Duration::from_secs(15), next_video_track(&mut events)).await;
    test_hooks::FAIL_REPEAT.store(false, Ordering::Relaxed);
    let moved = moved.expect("the share moved to VP9");
    let moved_after = failing.elapsed();
    let after = watch(&moved, Duration::from_secs(3)).await;
    let encoder = share_encoder().await;
    log::info!(
        "wgc share, encoder failing on a still picture: VP9's track {} ms after, {} frames \
         in 3 s, encoder {encoder}",
        moved_after.as_millis(),
        after.frames
    );
    assert!(
        moved_after < Duration::from_secs(4),
        "VP9 after {moved_after:?}"
    );
    assert_eq!(
        counts::HANDOVERS.load(Ordering::Relaxed),
        handovers,
        "waited for the new sessions"
    );
    assert_eq!(encoder, "libvpx");
    assert!(after.frames > 30, "{} frames on VP9", after.frames);
    let stopped = timeout(Duration::from_secs(5), session::stop())
        .await
        .expect("stop hung");
    assert_eq!(stopped.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}

/// A session that never gives a picture, from the share's start: run with
/// `RIFT_WGC_SILENT_AFTER=0`. The share is handed to libwebrtc's capturer in time
/// for its first picture, and starts.
#[cfg(target_os = "windows")]
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display, a hardware H264 encoder that takes textures and RIFT_WGC_SILENT_AFTER"]
async fn live_wgc_silent_from_the_start_moves_to_libwebrtc() {
    use super::capture_wgc::counts;
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    assert_eq!(
        std::env::var("RIFT_WGC_SILENT_AFTER").as_deref(),
        Ok("0"),
        "run with RIFT_WGC_SILENT_AFTER=0"
    );
    let server = Server::from_env();
    let room = live_room("wgc-silent-start");
    let title = "rift live test: silent start";
    let _window = test_window::TestWindow::open(title, true);
    let (viewer, mut events) = viewer_as(&server, &room, "viewer").await;
    let handovers = counts::HANDOVERS.load(Ordering::Relaxed);
    let starting = Instant::now();
    session::start(window_share(&server, &room, title))
        .await
        .expect("share starts");
    let started_after = starting.elapsed();
    let seen = watch(&next_video_track(&mut events).await, Duration::from_secs(3)).await;
    log::info!(
        "wgc share, silent from the start: started in {} ms, {} frames in 3 s",
        started_after.as_millis(),
        seen.frames
    );
    assert_eq!(
        counts::HANDOVERS.load(Ordering::Relaxed),
        handovers + 1,
        "not handed to libwebrtc's capturer"
    );
    assert!(seen.frames > 30, "{} frames", seen.frames);
    let stopped = timeout(Duration::from_secs(5), session::stop())
        .await
        .expect("stop hung");
    assert_eq!(stopped.unwrap(), "Stopped successfully");
    viewer.close().await.unwrap();
}
