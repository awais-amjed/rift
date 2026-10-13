//! A share's sound, published into a real room and heard by a real listener.
//!
//! Ignored by default: it needs a LiveKit server. Run it as the screen share's
//! live tests are run (`screenshare/live_test.rs`).
//!
//! What it proves: the two channels a share captures reach a listener as two.
//! A tone fed into only the left ear has to come out of only the left ear.
//! LiveKit encodes a track in mono unless the publisher says it is stereo,
//! and our fork of the SDK is what says so (`rust/Cargo.toml`).
use super::{publish_and_feed, Command, Pcm, NUM_CHANNELS, SAMPLE_RATE};
use crate::screenshare::live_test::{fresh_room, shared_key, viewer_as, Server, KEY_INDEX};
use futures_util::StreamExt;
use livekit::prelude::*;
use livekit::webrtc::audio_stream::native::NativeAudioStream;
use livekit::webrtc::stats::RtcStats;
use std::time::{Duration, Instant};
use tokio::time::timeout;

const FRAME_MS: u32 = 10;
/// Each ear has the tone alone for this long, in turn.
const SIDE_MS: u32 = 1_000;
const LISTEN: Duration = Duration::from_secs(6);
/// The quiet ear must sit this far under the loud one: a mono stream puts
/// the same level in both.
const SEPARATION: f64 = 10.0; // 20 dB

/// Interleaved stereo: a 1 kHz tone in the left ear, then in the right.
fn tone_frame(index: u32) -> Vec<i16> {
    let per_frame = SAMPLE_RATE * FRAME_MS / 1_000;
    let left = (index * FRAME_MS / SIDE_MS) % 2 == 0;
    let mut samples = Vec::with_capacity((per_frame * NUM_CHANNELS) as usize);
    for i in 0..per_frame {
        let t = (index * per_frame + i) as f64 / SAMPLE_RATE as f64;
        let v = ((t * 1_000.0 * std::f64::consts::TAU).sin() * 8_000.0) as i16;
        let (l, r) = if left { (v, 0) } else { (0, v) };
        samples.push(l);
        samples.push(r);
    }
    samples
}

/// Root mean square of each ear.
fn levels(data: &[i16]) -> (f64, f64) {
    let (mut l, mut r) = (0.0, 0.0);
    for pair in data.chunks_exact(2) {
        l += (pair[0] as f64).powi(2);
        r += (pair[1] as f64).powi(2);
    }
    let n = (data.len() / 2).max(1) as f64;
    ((l / n).sqrt(), (r / n).sqrt())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a LiveKit server"]
async fn live_share_sound_reaches_a_listener_in_stereo() {
    let _ = env_logger::try_init();
    let server = Server::from_env();
    let room_name = fresh_room();

    let sharer = crate::sharing::room::connect(
        &server.url,
        &server.token(&room_name, "sharer", false),
        &shared_key(),
        KEY_INDEX,
    )
    .await
    .expect("sharer connects");
    let (listener, mut events) = viewer_as(&server, &room_name, "listener").await;

    // Paced like a device, so the feed's catch-up has nothing to drop.
    let spawn: super::SpawnCapture = Box::new(|commands, frames| {
        std::thread::spawn(move || {
            let start = Instant::now();
            for index in 0.. {
                if commands.try_recv().is_ok_and(|c| matches!(c, Command::Terminate)) {
                    return;
                }
                let due = start + Duration::from_millis((index * FRAME_MS) as u64);
                std::thread::sleep(due.saturating_duration_since(Instant::now()));
                if frames.blocking_send(Pcm::read_now(tone_frame(index))).is_err() {
                    return;
                }
            }
        })
    });
    let handle = publish_and_feed(&sharer, spawn, "share-sound", None)
        .await
        .expect("sound publishes");

    let track = timeout(Duration::from_secs(20), async {
        loop {
            if let RoomEvent::TrackSubscribed {
                track: RemoteTrack::Audio(track),
                ..
            } = events.recv().await.expect("room events")
            {
                break track;
            }
        }
    })
    .await
    .expect("the listener gets the sound");

    let mut stream = NativeAudioStream::new(
        track.rtc_track(),
        SAMPLE_RATE as i32,
        NUM_CHANNELS as i32,
    );
    let (mut left_only, mut right_only, mut loud) = (0, 0, 0);
    let _ = timeout(LISTEN, async {
        while let Some(frame) = stream.next().await {
            let (l, r) = levels(&frame.data);
            if l.max(r) < 500.0 {
                continue;
            }
            loud += 1;
            if l > r * SEPARATION {
                left_only += 1;
            } else if r > l * SEPARATION {
                right_only += 1;
            }
        }
    })
    .await;

    let fmtp: Vec<String> = sharer
        .local_participant()
        .track_publications()
        .values()
        .filter_map(|p| p.track())
        .next()
        .expect("the published track")
        .get_stats()
        .await
        .unwrap_or_default()
        .into_iter()
        .filter_map(|s| match s {
            RtcStats::Codec(c) if c.codec.mime_type.contains("opus") => {
                Some(c.codec.sdp_fmtp_line)
            }
            _ => None,
        })
        .collect();
    log::info!("sent with {fmtp:?}; {loud} loud frames, {left_only} left only, {right_only} right only");

    handle.terminate();
    sharer.close().await.ok();
    listener.close().await.ok();

    assert!(loud > 100, "the listener heard {loud} frames of the tone");
    assert!(
        left_only > loud / 4 && right_only > loud / 4,
        "each ear should have the tone alone a good part of the time: \
         {left_only} left only, {right_only} right only, of {loud}"
    );
}
