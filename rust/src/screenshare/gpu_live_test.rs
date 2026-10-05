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
    self as share, ScreenShareConfig, SharePriority, ShareQuality,
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

struct ToSource(NativeVideoSource);

impl EncodedSink for ToSource {
    fn deliver(&mut self, frame: Encoded<'_>) {
        let (codec, long) = match frame.codec {
            GpuCodec::H264 => (
                EncodedVideoCodec::H264,
                h264::with_long_start_codes(frame.payload),
            ),
            GpuCodec::Av1 => (EncodedVideoCodec::AV1, None),
        };
        self.0.capture_encoded_frame(&EncodedVideoFrame {
            codec,
            payload: long.as_deref().unwrap_or(frame.payload),
            timestamp_us: frame.timestamp_us,
            frame_type: if frame.keyframe {
                EncodedFrameType::Key
            } else {
                EncodedFrameType::Delta
            },
            resolution: VideoResolution {
                width: WIDTH,
                height: HEIGHT,
            },
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

/// Frames a viewer decodes from 12 s of a picture: the GPU encoder's `gpu`
/// codec, or libwebrtc's own H264 encoder when that is `None`.
async fn decoded_frames(
    gpu: Option<GpuCodec>,
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
    let encoder = gpu.map(|codec| {
        GpuEncoder::open(
            EncoderSettings {
                codec,
                width: WIDTH,
                height: HEIGHT,
                fps: FPS,
                max_bitrate_bps: 4_000_000,
                start_bitrate_bps: 4_000_000,
            },
            Box::new(ToSource(source.clone())),
            None,
        )
        .expect("a hardware encoder opens")
    });
    let raw = source.clone();
    let track = LocalVideoTrack::create_video_track("screen_share", RtcVideoSource::Native(source));
    sharer
        .local_participant()
        .publish_track(
            LocalTrack::Video(track),
            TrackPublishOptions {
                source: TrackSource::Screenshare,
                video_codec: match gpu {
                    Some(GpuCodec::Av1) => VideoCodec::AV1,
                    _ => VideoCodec::H264,
                },
                video_encoder: if gpu.is_some() {
                    VideoEncoderBackend::PreEncoded
                } else {
                    VideoEncoderBackend::Auto
                },
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
    for (path, gpu) in [("gpu", Some(GpuCodec::H264)), ("software", None)] {
        if only.as_deref().is_some_and(|o| o != path) {
            continue;
        }
        seen_with_the_key_and_by_nobody_else(path, gpu).await;
    }
}

/// Fails today, and is the check to run when this changes: with encryption
/// on, no viewer gets a frame of AV1 from this SDK, the GPU's or libaom's
/// alike (Oct 5 2026). Unencrypted, every frame arrives. `ARCHITECTURE.md`,
/// "Encoding a share on the GPU", says why.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "fails until LiveKit's Rust SDK can send encrypted AV1; needs a LiveKit server and a hardware AV1 encoder"]
async fn live_gpu_av1_is_seen_with_the_key_and_by_nobody_else() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    seen_with_the_key_and_by_nobody_else("gpu AV1", Some(GpuCodec::Av1)).await;
}

/// For one way of encoding: a viewer with the call's key sees the picture,
/// and one without it or with the wrong key does not.
async fn seen_with_the_key_and_by_nobody_else(path: &str, gpu: Option<GpuCodec>) {
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
        livekit_url: server.url.clone(),
        livekit_token: server.token(room, "sharer", false),
        resolution: 1080,
        fps: 30,
        bitrate: 8,
        share_audio: false,
        capture_full_screen: true,
        selected_video_source_index: Some(0),
        codec: share::VideoCodec::H264,
        priority: SharePriority::Smoothness,
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
/// as VP9. Needs a display as well.
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
