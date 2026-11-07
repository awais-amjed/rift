//! How fast a fresh GPU share's rate climbs, printed every 2 s as `climb:` lines
//! to compare H265 with H264 on the same picture. It asserts nothing: it answers
//! a question. Each run is its own process, since pass-through is process-wide.
//!
//! `RIFT_CLIMB_CODEC` (h264, h265), `RIFT_CLIMB_WATCHER_AT` (seconds until a viewer
//! joins, 0 from the start), `RIFT_CLIMB_STILL` (seconds of a still picture first),
//! `RIFT_CLIMB_FOR` (seconds in all). Needs a LiveKit server (`live_test.rs`).
//!
//! `live_gpu_screen_share_rate_climb` does the same through the share itself, from
//! the real screen, for what capture and the rate gate add. `RIFT_PORTAL_TOKEN`
//! names the portal's token, and what moves on the screen is the caller's to arrange.
use super::encoder::{EncoderSettings, GpuCodec, GpuEncoder, Nv12Frame};
use super::gpu_live_test::{H265ToSource, ToSource};
use super::live_test::{shared_key, Server, KEY_INDEX};
use super::track::{publish_video_track, TrackSettings};
use crate::api::screenshare::types::{SharePriority, VideoCodec};
use crate::sharing::room;
use livekit::track::LocalTrack;
use livekit::webrtc::stats::RtcStats;
use livekit::webrtc::video_source::native::NativeVideoSource;
use livekit::webrtc::video_source::VideoResolution;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const WIDTH: u32 = 1920;
const HEIGHT: u32 = 1080;
const FPS: u32 = 60;
/// As the share's own `START_BITRATE_BPS`.
const START_BPS: u32 = 1_000_000;

fn seconds(name: &str, default: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

/// Noise in the top sixth and moving bands below: enough to fill any rate the
/// share may be given, for the same cost to either codec's encoder here.
fn picture(data: &mut [u8], noise: &[u8], moved: u32) {
    let luma = (WIDTH * HEIGHT) as usize;
    let noise_to = luma / 6;
    let from = (moved as usize).wrapping_mul(7919) % (noise.len() - noise_to);
    data[..noise_to].copy_from_slice(&noise[from..from + noise_to]);
    for (row, line) in data[noise_to..luma].chunks_mut(WIDTH as usize).enumerate() {
        line.fill((row as u32).wrapping_add(moved * 3) as u8);
    }
    data[luma..].fill(128);
}

fn noise() -> Vec<u8> {
    let mut bits = 0x9e37_79b9u32;
    (0..(WIDTH * HEIGHT) as usize)
        .map(|_| {
            bits ^= bits << 13;
            bits ^= bits >> 17;
            bits ^= bits << 5;
            (bits >> 24) as u8
        })
        .collect()
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server; see the module doc"]
async fn live_gpu_share_rate_climb() {
    let _ = env_logger::builder().is_test(true).try_init();
    let (codec, share_codec, cap_mbps) = match std::env::var("RIFT_CLIMB_CODEC").as_deref() {
        Ok("h264") => (GpuCodec::H264, VideoCodec::H264, 12),
        _ => (GpuCodec::H265, VideoCodec::H265, 11),
    };
    let watcher_at = seconds("RIFT_CLIMB_WATCHER_AT", 0);
    let still = seconds("RIFT_CLIMB_STILL", 0);
    let run_for = seconds("RIFT_CLIMB_FOR", 60);

    // As an app whose watched shares decode on the GPU: only that offers H265.
    crate::watching::decode::choose();
    crate::watching::decode::gpu().expect("decoding on the GPU here");

    let server = Server::from_env();
    let key = shared_key();
    let name = format!(
        "rift-climb-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis()
    );
    let connect_viewer = || async {
        room::connect(
            &server.url,
            // Not a `_watch` identity: the server's webhook removes one with no voice
            // connection beside it.
            &server.token(&name, "viewer~laptop", true),
            &key,
            KEY_INDEX,
        )
        .await
        .expect("the viewer connects")
    };
    let mut viewer = if watcher_at == 0 {
        Some(connect_viewer().await)
    } else {
        None
    };
    let sharer = room::connect(
        &server.url,
        &server.token(&name, "member~desk_share", false),
        &key,
        KEY_INDEX,
    )
    .await
    .expect("the sharer connects");

    let source = NativeVideoSource::new_encoded(VideoResolution {
        width: WIDTH,
        height: HEIGHT,
    });
    let settings = EncoderSettings {
        codec,
        width: WIDTH,
        height: HEIGHT,
        fps: FPS,
        max_bitrate_bps: cap_mbps * 1_000_000,
        start_bitrate_bps: START_BPS,
        h264_high: true,
        gpu_capture: true,
    };
    let encoder = GpuEncoder::open(
        settings,
        match codec {
            GpuCodec::H264 => Box::new(ToSource(source.clone())),
            GpuCodec::H265 => Box::new(H265ToSource(source.clone())),
        },
    )
    .expect("a hardware encoder opens");
    log::info!("climb: encoding on {}", encoder.name());

    let target = Arc::new(AtomicU32::new(START_BPS));
    let stop = Arc::new(AtomicBool::new(false));
    let began = Instant::now();
    let feeding = {
        let (target, stop) = (target.clone(), stop.clone());
        tokio::task::spawn_blocking(move || {
            let noise = noise();
            let len = Nv12Frame::len_for(WIDTH, HEIGHT);
            let mut moved = 0;
            let frame = Duration::from_micros(1_000_000 / u64::from(FPS));
            let mut next = Instant::now();
            while !stop.load(Ordering::SeqCst) {
                if began.elapsed().as_secs() >= still {
                    moved += 1;
                }
                let mut data = encoder.buffer(len);
                picture(&mut data, &noise, moved);
                let timestamp_us = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_micros() as i64;
                encoder.submit(Nv12Frame { data, timestamp_us });
                target.store(encoder.bitrate(), Ordering::Relaxed);
                next += frame;
                std::thread::sleep(next.saturating_duration_since(Instant::now()));
            }
        })
    };

    publish_video_track(
        &sharer.local_participant(),
        source,
        &TrackSettings {
            max_height: HEIGHT,
            fps: FPS,
            bitrate: cap_mbps,
            codec: share_codec,
            priority: SharePriority::Smoothness,
            gpu_capture: true,
        },
        Some(&settings),
    )
    .await
    .expect("publishes");
    let track = sharer
        .local_participant()
        .track_publications()
        .into_values()
        .find_map(|publication| publication.track())
        .and_then(|track| match track {
            LocalTrack::Video(track) => Some(track),
            _ => None,
        })
        .expect("the published track");

    let (mut last_sent, mut last_retx, mut last_at) = (0u64, 0u64, Instant::now());
    while began.elapsed() < Duration::from_secs(run_for) {
        tokio::time::sleep(Duration::from_secs(2)).await;
        if viewer.is_none() && began.elapsed().as_secs() >= watcher_at {
            viewer = Some(connect_viewer().await);
            log::info!("climb: viewer joined at {} s", began.elapsed().as_secs());
        }
        let (mut available, mut sent, mut retx, mut active) = (0.0, 0, 0, false);
        for stat in track.get_stats().await.unwrap_or_default() {
            match stat {
                RtcStats::CandidatePair(pair) if pair.candidate_pair.nominated => {
                    available = pair.candidate_pair.available_outgoing_bitrate;
                }
                RtcStats::OutboundRtp(rtp) => {
                    sent += rtp.sent.bytes_sent;
                    retx += rtp.outbound.retransmitted_bytes_sent;
                    active |= rtp.outbound.active;
                }
                _ => {}
            }
        }
        let spent = last_at.elapsed().as_secs_f64();
        log::info!(
            "climb: t={:>3} codec={codec} target={:>5}k available={:>6.0}k sent={:>6.0}k retx={:>4.0}k active={active}",
            began.elapsed().as_secs(),
            target.load(Ordering::Relaxed) / 1000,
            available / 1000.0,
            (sent - last_sent) as f64 * 8.0 / spent / 1000.0,
            (retx - last_retx) as f64 * 8.0 / spent / 1000.0,
        );
        (last_sent, last_retx, last_at) = (sent, retx, Instant::now());
    }

    stop.store(true, Ordering::SeqCst);
    let _ = feeding.await;
    let _ = sharer.close().await;
    if let Some(viewer) = viewer {
        let _ = viewer.close().await;
    }
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a screen; see the module doc"]
async fn live_gpu_screen_share_rate_climb() {
    use super::encoder::test_hooks::LAST_RATE;
    use crate::api::screenshare::types::ScreenShareConfig;
    use livekit::track::RemoteTrack;

    let _ = env_logger::builder().is_test(true).try_init();
    let (codec, cap_mbps) = match std::env::var("RIFT_CLIMB_CODEC").as_deref() {
        Ok("h264") => (VideoCodec::H264, 12),
        _ => (VideoCodec::H265, 11),
    };
    let watcher_at = seconds("RIFT_CLIMB_WATCHER_AT", 0);
    let run_for = seconds("RIFT_CLIMB_FOR", 60);
    crate::watching::decode::choose();

    let server = Server::from_env();
    let key = shared_key();
    let name = format!(
        "rift-climb-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis()
    );
    let connect_viewer = || async {
        room::connect(
            &server.url,
            &server.token(&name, "viewer~laptop", true),
            &key,
            KEY_INDEX,
        )
        .await
        .expect("the viewer connects")
    };
    let mut viewer = if watcher_at == 0 {
        Some(connect_viewer().await)
    } else {
        None
    };
    super::sources::list(true);
    let began = Instant::now();
    super::session::start(ScreenShareConfig {
        gpu_capture: true,
        livekit_url: server.url.clone(),
        livekit_token: server.token(&name, "sharer~laptop_share", false),
        resolution: HEIGHT,
        fps: FPS,
        bitrate: cap_mbps,
        share_audio: false,
        capture_full_screen: true,
        selected_video_source_index: Some(0),
        portal_choice: None,
        codec,
        priority: SharePriority::Smoothness,
        selected_audio_source_index: None,
        selected_audio_source_sink: None,
        selected_audio_source_pid: None,
        e2ee_key: key.clone(),
        e2ee_key_index: KEY_INDEX,
    })
    .await
    .expect("the share starts");
    log::info!("climb: share up at {:.1} s", began.elapsed().as_secs_f64());

    let (mut last_got, mut last_frames, mut last_at) = (0u64, 0u64, Instant::now());
    while began.elapsed() < Duration::from_secs(run_for) {
        tokio::time::sleep(Duration::from_secs(2)).await;
        if viewer.is_none() && began.elapsed().as_secs() >= watcher_at {
            viewer = Some(connect_viewer().await);
            log::info!("climb: viewer joined at {} s", began.elapsed().as_secs());
        }
        let (mut got, mut frames, mut named) = (0, 0, String::new());
        let tracks: Vec<_> = viewer
            .iter()
            .flat_map(|viewer| viewer.remote_participants().into_values())
            .flat_map(|participant| participant.track_publications().into_values())
            .filter_map(|publication| publication.track())
            .collect();
        for track in tracks {
            if let RemoteTrack::Video(track) = track {
                for stat in track.get_stats().await.unwrap_or_default() {
                    if let RtcStats::InboundRtp(rtp) = stat {
                        got += rtp.inbound.bytes_received;
                        frames += rtp.inbound.frames_received;
                        named = rtp.inbound.decoder_implementation.clone();
                    }
                }
            }
        }
        let spent = last_at.elapsed().as_secs_f64();
        log::info!(
            "climb: t={:>3} codec={codec:?} target={:>5}k got={:>6.0}k fps={:>3.0} {named}",
            began.elapsed().as_secs(),
            LAST_RATE.load(Ordering::Relaxed) / 1000,
            got.saturating_sub(last_got) as f64 * 8.0 / spent / 1000.0,
            frames.saturating_sub(last_frames) as f64 / spent,
        );
        (last_got, last_frames, last_at) = (got, frames, Instant::now());
    }

    let _ = super::session::stop().await;
    if let Some(viewer) = viewer {
        let _ = viewer.close().await;
    }
}
