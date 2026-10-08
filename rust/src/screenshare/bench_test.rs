//! How much a share costs and how smoothly it arrives: the numbers GPU
//! encoding has to beat.
//!
//! Two processes, so the viewer's decoding is not billed to the share. Start
//! the viewer, then the share, with the same room and server:
//!
//! ```text
//! LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret \
//! BENCH_ROOM=bench-1 BENCH_SECS=30 cargo test bench_view -- --ignored --nocapture
//!
//! … BENCH_CODEC=vp9 BENCH_HEIGHT=1080 BENCH_FPS=60 BENCH_MBPS=10 \
//!   cargo test bench_share -- --ignored --nocapture
//! ```
//!
//! The share captures the first screen, so put something moving on it first,
//! or the first window whose title contains `BENCH_WINDOW`. On Linux under
//! Wayland only a window works: the X11 capturer sees no screen there, only
//! X11 windows, and a still picture costs nothing to encode.
//! Each side waits [`WARMUP`] before it starts counting, then reports over
//! `BENCH_SECS`: the share once for each simulcast layer, and both every
//! [`SAMPLE`] as well, so a move between layers shows, or the share falling
//! behind on a slow link. More viewers take a `BENCH_VIEWER` name each.
use super::live_test::Server;
use super::session;
use crate::api::screenshare::types::{ScreenShareConfig, SharePriority, VideoCodec};
use futures_util::StreamExt;
use livekit::prelude::*;
use livekit::webrtc::stats::RtcStats;
use livekit::webrtc::video_stream::native::NativeVideoStream;
use std::time::{Duration, Instant};
use tokio::time::timeout;

const WARMUP: Duration = Duration::from_secs(5);
/// How often the viewer reports what it is getting.
const SAMPLE: Duration = Duration::from_secs(2);
/// How long the share stays up after its own count, so the viewer's count,
/// which started a little later, ends while there is still a picture.
const TAIL: Duration = Duration::from_secs(10);

fn env_or(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_string())
}

fn env_num(name: &str, default: u32) -> u32 {
    env_or(name, &default.to_string())
        .parse()
        .unwrap_or_else(|_| panic!("{name} is not a number"))
}

fn bench_secs() -> Duration {
    Duration::from_secs(env_num("BENCH_SECS", 30).into())
}

fn codec() -> VideoCodec {
    match env_or("BENCH_CODEC", "vp9").to_lowercase().as_str() {
        "h264" => VideoCodec::H264,
        "vp8" => VideoCodec::VP8,
        "vp9" => VideoCodec::VP9,
        other => panic!("BENCH_CODEC {other} is not h264, vp8 or vp9"),
    }
}

/// This process's CPU time so far, user and kernel together.
#[cfg(target_os = "windows")]
fn cpu_time() -> Duration {
    use windows::Win32::Foundation::FILETIME;
    use windows::Win32::System::Threading::{GetCurrentProcess, GetProcessTimes};
    let (mut created, mut exited, mut kernel, mut user) = (
        FILETIME::default(),
        FILETIME::default(),
        FILETIME::default(),
        FILETIME::default(),
    );
    unsafe {
        GetProcessTimes(
            GetCurrentProcess(),
            &mut created,
            &mut exited,
            &mut kernel,
            &mut user,
        )
        .expect("process times");
    }
    let ticks = |t: FILETIME| (u64::from(t.dwHighDateTime) << 32) | u64::from(t.dwLowDateTime);
    // FILETIME counts 100 ns ticks.
    Duration::from_nanos((ticks(kernel) + ticks(user)) * 100)
}

#[cfg(not(target_os = "windows"))]
fn cpu_time() -> Duration {
    // utime and stime, fields 14 and 15, in clock ticks of 1/100 s.
    let stat = std::fs::read_to_string("/proc/self/stat").unwrap_or_default();
    let after_name = stat.rsplit(')').next().unwrap_or("");
    let fields: Vec<u64> = after_name
        .split_whitespace()
        .map(|f| f.parse().unwrap_or(0))
        .collect();
    let ticks = fields.get(11).unwrap_or(&0) + fields.get(12).unwrap_or(&0);
    Duration::from_millis(ticks * 10)
}

/// The share's outgoing pictures: one, or one per simulcast layer, largest
/// last.
fn outbound(stats: &[RtcStats]) -> Vec<&livekit::webrtc::stats::OutboundRtpStats> {
    let mut layers: Vec<_> = stats
        .iter()
        .filter_map(|s| match s {
            RtcStats::OutboundRtp(o) if o.stream.kind == "video" => Some(o),
            _ => None,
        })
        .collect();
    layers.sort_by_key(|o| o.outbound.frame_width);
    layers
}

/// What went out in one stretch, and how late: the time packets waited in
/// WebRTC's send queue, and the round trip to the server, which grows with a
/// queue on the way there. Either one climbing is the picture falling behind
/// its sound.
fn log_sending(last: &[RtcStats], now: &[RtcStats], elapsed: Duration) {
    let (Some(p), Some(n)) = (outbound(last).pop(), outbound(now).pop()) else {
        return;
    };
    let packets = n.sent.packets_sent - p.sent.packets_sent;
    let queued_ms = if packets > 0 {
        (n.outbound.total_packet_send_delay - p.outbound.total_packet_send_delay) * 1000.0
            / packets as f64
    } else {
        0.0
    };
    let rtt_ms = now
        .iter()
        .find_map(|s| match s {
            RtcStats::RemoteInboundRtp(r) if r.stream.kind == "video" => {
                Some(r.remote_inbound.round_trip_time * 1000.0)
            }
            _ => None,
        })
        .unwrap_or(0.0);
    log::info!(
        "bench share: {:>4.0} s | {:.1} fps sent | {:.2} Mbps sent, target {:.2} | \
         queued {:.0} ms | round trip {:.0} ms | keyframes {}",
        elapsed.as_secs_f64(),
        f64::from(n.outbound.frames_sent - p.outbound.frames_sent) / SAMPLE.as_secs_f64(),
        (n.sent.bytes_sent - p.sent.bytes_sent) as f64 * 8.0 / SAMPLE.as_secs_f64() / 1e6,
        n.outbound.target_bitrate / 1e6,
        queued_ms,
        rtt_ms,
        n.outbound.key_frames_encoded - p.outbound.key_frames_encoded,
    );
}

fn inbound(stats: &[RtcStats]) -> Option<&livekit::webrtc::stats::InboundRtpStats> {
    stats.iter().find_map(|s| match s {
        RtcStats::InboundRtp(i) if i.stream.kind == "video" => Some(i),
        _ => None,
    })
}

/// What to share: the first window titled with `BENCH_WINDOW` if it is set,
/// the first screen otherwise. Listed first, as the app lists before it
/// shares.
fn source() -> (bool, u32) {
    let Ok(wanted) = std::env::var("BENCH_WINDOW") else {
        super::sources::list(true);
        return (true, 0);
    };
    let window = super::sources::list(false)
        .into_iter()
        .find(|source| source.title.contains(&wanted))
        .unwrap_or_else(|| panic!("no window titled {wanted:?}"));
    (false, window.index)
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server, a display and a viewer; see the module doc"]
async fn bench_share() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = env_or("BENCH_ROOM", "bench");
    // BENCH_OVERSHOOT=1: an encoder that ignores the connection, to see what
    // a capped link does with the excess.
    super::encoder::test_hooks::IGNORE_RATE.store(
        env_or("BENCH_OVERSHOOT", "0") == "1",
        std::sync::atomic::Ordering::Relaxed,
    );
    let (full_screen, index) = source();
    let config = ScreenShareConfig {
        livekit_url: server.url.clone(),
        livekit_token: server.token(&room, "sharer", false),
        resolution: env_num("BENCH_HEIGHT", 1080),
        fps: env_num("BENCH_FPS", 60),
        bitrate: env_num("BENCH_MBPS", 10),
        share_audio: false,
        capture_full_screen: full_screen,
        selected_video_source_index: Some(index),
        codec: codec(),
        priority: SharePriority::Smoothness,
        selected_audio_source_index: None,
        selected_audio_source_sink: None,
        selected_audio_source_pid: None,
        e2ee_key: super::live_test::shared_key(),
        e2ee_key_index: super::live_test::KEY_INDEX,
    };
    session::start(config).await.expect("share starts");
    tokio::time::sleep(WARMUP).await;

    let before_stats = session::video_stats().await.expect("stats");
    let before_cpu = cpu_time();
    let started = Instant::now();
    let mut last = before_stats.clone();
    while started.elapsed() < bench_secs() {
        tokio::time::sleep(SAMPLE.min(bench_secs().saturating_sub(started.elapsed()))).await;
        let now = session::video_stats().await.expect("stats");
        log_sending(&last, &now, started.elapsed());
        last = now;
    }
    let wall = started.elapsed().as_secs_f64();
    let cpu = (cpu_time() - before_cpu).as_secs_f64();
    let after_stats = session::video_stats().await.expect("stats");
    tokio::time::sleep(TAIL).await;
    session::stop().await.expect("share stops");

    let before = outbound(&before_stats);
    let after = outbound(&after_stats);
    assert!(!after.is_empty(), "outbound video stats");
    let cores = std::thread::available_parallelism().map_or(1, |n| n.get()) as f64;
    let mut total_mbps = 0.0;
    for b in &after {
        let a = before
            .iter()
            .find(|a| a.outbound.rid == b.outbound.rid)
            .expect("the same layers before and after");
        let encoded = f64::from(b.outbound.frames_encoded - a.outbound.frames_encoded);
        let sent = f64::from(b.outbound.frames_sent - a.outbound.frames_sent);
        let encode_ms = (b.outbound.total_encode_time - a.outbound.total_encode_time) * 1000.0;
        let mbps = (b.sent.bytes_sent - a.sent.bytes_sent) as f64 * 8.0 / wall / 1e6;
        total_mbps += mbps;
        log::info!(
            "bench share: layer {:?} {} {}x{} | active {} | encoder {:?} | {:.1} fps encoded, \
             {:.1} fps sent | {:.2} ms encode/frame | {:.2} Mbps sent, target {:.2} | \
             keyframes {} | limited by {:?} {:?}",
            b.outbound.rid,
            env_or("BENCH_CODEC", "vp9"),
            b.outbound.frame_width,
            b.outbound.frame_height,
            b.outbound.active,
            b.outbound.encoder_implementation,
            encoded / wall,
            sent / wall,
            if encoded > 0.0 {
                encode_ms / encoded
            } else {
                0.0
            },
            mbps,
            b.outbound.target_bitrate / 1e6,
            b.outbound.key_frames_encoded - a.outbound.key_frames_encoded,
            b.outbound.quality_limitation_reason,
            b.outbound.quality_limitation_durations,
        );
    }
    log::info!(
        "bench share: {} layers | {:.2} Mbps sent | CPU {:.0}% of one core, {:.1}% of {cores} | {:.1} s",
        after.len(),
        total_mbps,
        cpu / wall * 100.0,
        cpu / wall / cores * 100.0,
        wall,
    );
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server and a share to watch; see the module doc"]
async fn bench_view() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
    let server = Server::from_env();
    let room = env_or("BENCH_ROOM", "bench");
    let joined = Instant::now();
    let identity = env_or("BENCH_VIEWER", "viewer");
    let (viewer, mut events) = super::live_test::viewer_as(&server, &room, &identity).await;
    let track = timeout(Duration::from_secs(120), async {
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
    .expect("a share to watch");

    // Say what the room says about encryption while the picture comes in:
    // a frame that cannot be decrypted is never decoded, and nothing else
    // tells the two apart.
    let watch = tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            if let RoomEvent::E2eeStateChanged { participant, state } = event {
                log::info!(
                    "bench view: encryption {state:?} for {}",
                    participant.identity()
                );
            }
        }
    });
    let mut stream = NativeVideoStream::new(track.rtc_track());
    let first = timeout(Duration::from_secs(20), stream.next()).await;
    if !matches!(first, Ok(Some(_))) {
        let stats = track.get_stats().await.expect("stats");
        if let Some(i) = inbound(&stats) {
            log::info!(
                "bench view: no picture: decoder {:?}, {} frames received, {} decoded,                  {} keyframes decoded, {} dropped, {} PLIs, {} packets, {} bytes",
                i.inbound.decoder_implementation,
                i.inbound.frames_received,
                i.inbound.frames_decoded,
                i.inbound.key_frames_decoded,
                i.inbound.frames_dropped,
                i.inbound.pli_count,
                i.received.packets_received,
                i.inbound.bytes_received,
            );
        }
        panic!("no picture in 20 s");
    }
    watch.abort();
    log::info!(
        "bench view: first frame {:.0} ms after joining",
        joined.elapsed().as_secs_f64() * 1000.0
    );
    // Drain frames for the rest of the run, as a real viewer's renderer does.
    let drain = tokio::spawn(async move { while stream.next().await.is_some() {} });

    tokio::time::sleep(WARMUP).await;
    let a = track.get_stats().await.expect("stats");
    let started = Instant::now();
    // What arrived in each stretch, to see the server move this viewer
    // between a share's layers.
    let mut last = a.clone();
    while started.elapsed() < bench_secs() {
        tokio::time::sleep(SAMPLE).await;
        let now = track.get_stats().await.expect("stats");
        if let (Some(p), Some(n)) = (inbound(&last), inbound(&now)) {
            log::info!(
                "bench view: {:>4.0} s | {}x{} | {:.1} fps | {:.2} Mbps | freezes {} | lost {}",
                started.elapsed().as_secs_f64(),
                n.inbound.frame_width,
                n.inbound.frame_height,
                f64::from(n.inbound.frames_decoded - p.inbound.frames_decoded)
                    / SAMPLE.as_secs_f64(),
                (n.inbound.bytes_received - p.inbound.bytes_received) as f64 * 8.0
                    / SAMPLE.as_secs_f64()
                    / 1e6,
                n.inbound.freeze_count - p.inbound.freeze_count,
                n.received.packets_lost - p.received.packets_lost,
            );
        }
        last = now;
    }
    let wall = started.elapsed().as_secs_f64();
    let b = track.get_stats().await.expect("stats");
    drain.abort();
    viewer.close().await.unwrap();

    let a = inbound(&a).expect("inbound video stats");
    let b = inbound(&b).expect("inbound video stats");
    let decoded = f64::from(b.inbound.frames_decoded - a.inbound.frames_decoded);
    log::info!(
        "bench view: decoder {:?} {}x{} | {:.1} fps decoded | dropped {} | freezes {} ({:.2} s) | \
         keyframes {} | PLIs {} | {:.2} Mbps | {:.1} s",
        b.inbound.decoder_implementation,
        b.inbound.frame_width,
        b.inbound.frame_height,
        decoded / wall,
        b.inbound.frames_dropped - a.inbound.frames_dropped,
        b.inbound.freeze_count - a.inbound.freeze_count,
        b.inbound.total_freeze_duration - a.inbound.total_freeze_duration,
        b.inbound.key_frames_decoded - a.inbound.key_frames_decoded,
        b.inbound.pli_count - a.inbound.pli_count,
        (b.inbound.bytes_received - a.inbound.bytes_received) as f64 * 8.0 / wall / 1e6,
        wall,
    );
}
