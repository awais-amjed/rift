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
//! The share captures the first screen, so put something moving on it first.
//! Each side waits [`WARMUP`] before it starts counting, then reports over
//! `BENCH_SECS`.
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

fn outbound(stats: &[RtcStats]) -> Option<&livekit::webrtc::stats::OutboundRtpStats> {
    stats.iter().find_map(|s| match s {
        RtcStats::OutboundRtp(o) if o.stream.kind == "video" => Some(o),
        _ => None,
    })
}

fn inbound(stats: &[RtcStats]) -> Option<&livekit::webrtc::stats::InboundRtpStats> {
    stats.iter().find_map(|s| match s {
        RtcStats::InboundRtp(i) if i.stream.kind == "video" => Some(i),
        _ => None,
    })
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
    super::sources::list(true);
    let config = ScreenShareConfig {
        livekit_url: server.url.clone(),
        livekit_token: server.token(&room, "sharer", false),
        resolution: env_num("BENCH_HEIGHT", 1080),
        fps: env_num("BENCH_FPS", 60),
        bitrate: env_num("BENCH_MBPS", 10),
        share_audio: false,
        capture_full_screen: true,
        selected_video_source_index: Some(0),
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
    tokio::time::sleep(bench_secs()).await;
    let wall = started.elapsed().as_secs_f64();
    let cpu = (cpu_time() - before_cpu).as_secs_f64();
    let after_stats = session::video_stats().await.expect("stats");
    tokio::time::sleep(TAIL).await;
    session::stop().await.expect("share stops");

    let a = outbound(&before_stats).expect("outbound video stats");
    let b = outbound(&after_stats).expect("outbound video stats");
    let encoded = f64::from(b.outbound.frames_encoded - a.outbound.frames_encoded);
    let sent = f64::from(b.outbound.frames_sent - a.outbound.frames_sent);
    let encode_ms = (b.outbound.total_encode_time - a.outbound.total_encode_time) * 1000.0;
    let mbps = (b.sent.bytes_sent - a.sent.bytes_sent) as f64 * 8.0 / wall / 1e6;
    let cores = std::thread::available_parallelism().map_or(1, |n| n.get()) as f64;
    log::info!(
        "bench share: {} {}x{} | encoder {:?} | {:.1} fps encoded, {:.1} fps sent | \
         {:.2} ms encode/frame | {:.2} Mbps sent, target {:.2} | keyframes {} | \
         limited by {:?} {:?} | CPU {:.0}% of one core, {:.1}% of {cores} | {:.1} s",
        env_or("BENCH_CODEC", "vp9"),
        b.outbound.frame_width,
        b.outbound.frame_height,
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
    let (viewer, mut events) = super::live_test::viewer_as(&server, &room, "viewer").await;
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
    tokio::time::sleep(bench_secs()).await;
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
