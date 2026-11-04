//! A watched share's sound, received on the watch connection and played by
//! Rust itself, on the output chosen in settings, at the volume the app hands
//! down (`set_volume`): the share's own volume times the call's, and nothing
//! while it is muted or this device is deafened. The call's own copy of the
//! sound is held meanwhile, so it plays once.
//!
//! Stereo and full band. The call's playback runs the share's sound through
//! libwebrtc's processing at 32 kHz, which cut it off at about 15 kHz
//! (`CALLS.md`). It also keeps the sound beside its picture: both come off one
//! connection, which holds the picture back to the sound's pace.
//!
//! Each share plays on a thread of its own, fed by a task reading the track;
//! the thread ends when the task does. Each platform supplies `run`, which
//! opens the output and plays what it is fed until the feed ends. Where there
//! is none yet ([`PLAYS`] false), the share's sound stays with the call.

use futures_util::StreamExt;
use livekit::prelude::RemoteAudioTrack;
use livekit::webrtc::audio_stream::native::NativeAudioStream;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::mpsc::{self, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread;
use tokio::task::JoinHandle;

#[cfg(not(any(target_os = "linux", windows)))]
mod elsewhere;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(windows)]
mod windows;

#[cfg(not(any(target_os = "linux", windows)))]
use elsewhere::run;
#[cfg(not(any(target_os = "linux", windows)))]
pub(crate) use elsewhere::PLAYS;
#[cfg(target_os = "linux")]
use linux::run;
#[cfg(target_os = "linux")]
pub(crate) use linux::PLAYS;
#[cfg(windows)]
use windows::run;
#[cfg(windows)]
pub(crate) use windows::PLAYS;

const SAMPLE_RATE: u32 = 48_000;
const CHANNELS: u32 = 2;

/// How many 10 ms frames may wait for the player: enough to ride out a late
/// wake, after which the newest are dropped rather than queued, so the sound
/// never falls behind its picture for good.
const QUEUED_FRAMES: usize = 8;

/// How loud a share plays, shared between the session, which the app sets
/// it through, and the thread playing it. An `f32`'s bits.
#[derive(Default)]
pub(crate) struct Gain(AtomicU32);

impl Gain {
    pub(crate) fn set(&self, gain: f32) {
        self.0.store(gain.max(0.0).to_bits(), Ordering::Relaxed);
    }

    pub(crate) fn get(&self) -> f32 {
        f32::from_bits(self.0.load(Ordering::Relaxed))
    }
}

/// A share's sound playing. Dropped, it stops: the feed ends, and the
/// thread with it, within one wait of the player's.
pub(crate) struct Playing {
    feed: JoinHandle<()>,
}

impl Drop for Playing {
    fn drop(&mut self) {
        self.feed.abort();
    }
}

/// Plays `track` at `gain`; None where this build has no player, or no
/// thread could be had for it.
pub(crate) fn play(track: RemoteAudioTrack, gain: Arc<Gain>) -> Option<Playing> {
    if !PLAYS {
        return None;
    }
    let (frames, feed) = mpsc::sync_channel::<Vec<i16>>(QUEUED_FRAMES);
    start_player(feed, gain, run)
        .map_err(|e| log::warn!("watching: no thread for the sound: {e}"))
        .ok()?;
    let feed = tokio::spawn(async move {
        let mut stream =
            NativeAudioStream::new(track.rtc_track(), SAMPLE_RATE as i32, CHANNELS as i32);
        while let Some(frame) = stream.next().await {
            match frames.try_send(frame.data.into_owned()) {
                Ok(()) | Err(TrySendError::Full(_)) => {}
                // The player gave up: its output went away.
                Err(TrySendError::Disconnected(_)) => break,
            }
        }
    });
    Some(Playing { feed })
}

/// What plays a share's sound: Ok once its feed has ended, as when the share
/// is unwatched; an error when it could not go on.
type Run = fn(mpsc::Receiver<Vec<i16>>, &Gain) -> Result<(), String>;

/// Plays [feed] on a thread of its own. A player that fails gives the share
/// back to the call's connection: the call's copy of the sound is held while
/// Rust plays it, so a player that just stopped left the share silent with
/// nothing to say why.
fn start_player(
    feed: mpsc::Receiver<Vec<i16>>,
    gain: Arc<Gain>,
    run: Run,
) -> std::io::Result<thread::JoinHandle<()>> {
    thread::Builder::new()
        .name("rift-watch-sound".to_string())
        .spawn(move || {
            if let Err(why) = run(feed, &gain) {
                log::warn!("watching: {why}");
                super::session::lost(&format!("the share's sound stopped: {why}"));
            }
        })
}

/// The output chosen in settings, as WebRTC lists it (None for the default),
/// and how many times it has changed, which tells a playing share to move.
static OUTPUT: Mutex<Option<String>> = Mutex::new(None);
static OUTPUT_CHANGES: AtomicU64 = AtomicU64::new(0);

/// Moves every share's sound to `device_id`, now and from then on.
pub(crate) fn set_output(device_id: Option<String>) {
    let mut output = OUTPUT.lock().unwrap_or_else(|e| e.into_inner());
    if *output != device_id {
        *output = device_id;
        OUTPUT_CHANGES.fetch_add(1, Ordering::SeqCst);
    }
}

/// The output to play on, and the change it is: read the change first, so a
/// move made in between is seen on the next look rather than lost.
#[cfg_attr(not(any(target_os = "linux", windows)), allow(dead_code))]
fn output() -> (u64, Option<String>) {
    let changes = OUTPUT_CHANGES.load(Ordering::SeqCst);
    let device = OUTPUT.lock().unwrap_or_else(|e| e.into_inner()).clone();
    (changes, device)
}

#[cfg_attr(not(any(target_os = "linux", windows)), allow(dead_code))]
fn output_changes() -> u64 {
    OUTPUT_CHANGES.load(Ordering::SeqCst)
}

/// What of the interleaved stereo `samples` to play when the output has
/// `room` samples free, at `gain`. The rest is dropped rather than held: held,
/// it would put the sound behind its picture for good. Whole frames only, so
/// left stays left.
#[cfg_attr(not(any(target_os = "linux", windows)), allow(dead_code))]
fn playable(samples: &[i16], room: usize, gain: f32) -> Vec<i16> {
    let take = samples.len().min(room) / CHANNELS as usize * CHANNELS as usize;
    samples[..take]
        .iter()
        .map(|&s| (f32::from(s) * gain).round().clamp(-32768.0, 32767.0) as i16)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_player_that_fails_gives_the_sound_back_to_the_call() {
        fn fails(_: mpsc::Receiver<Vec<i16>>, _: &Gain) -> Result<(), String> {
            Err("output 7 would not open".to_string())
        }
        fn ends(frames: mpsc::Receiver<Vec<i16>>, _: &Gain) -> Result<(), String> {
            while frames.recv().is_ok() {}
            Ok(())
        }
        let (_frames, feed) = mpsc::sync_channel(1);
        start_player(feed, Arc::default(), fails)
            .unwrap()
            .join()
            .unwrap();
        let lost = crate::watching::session::lost_reasons();
        assert!(
            lost.iter().any(|r| r.contains("output 7 would not open")),
            "{lost:?}"
        );

        // Fed to its end, as when the share is unwatched: nothing is lost.
        let (frames, feed) = mpsc::sync_channel(1);
        let player = start_player(feed, Arc::default(), ends).unwrap();
        drop(frames);
        player.join().unwrap();
        let after = crate::watching::session::lost_reasons();
        assert!(
            !after[lost.len()..].iter().any(|r| r.contains("sound")),
            "{after:?}"
        );
    }

    #[test]
    fn plays_what_fits_at_the_gain() {
        assert_eq!(
            playable(&[100, -100, 300, 5], 8, 0.5),
            vec![50, -50, 150, 3]
        );
        assert_eq!(playable(&[100, -100, 300, 5], 2, 1.0), vec![100, -100]);
        assert!(playable(&[100, -100], 0, 1.0).is_empty());
    }

    #[test]
    fn keeps_left_and_right_paired() {
        assert_eq!(playable(&[1, 2, 3, 4], 3, 1.0), vec![1, 2]);
    }

    #[test]
    fn loud_gains_clip_rather_than_wrap() {
        assert_eq!(
            playable(&[20_000, -20_000], 2, 8.0),
            vec![i16::MAX, i16::MIN]
        );
    }

    #[test]
    fn a_gain_never_goes_below_nothing() {
        let gain = Gain::default();
        assert_eq!(gain.get(), 0.0);
        gain.set(-1.0);
        assert_eq!(gain.get(), 0.0);
        gain.set(2.5);
        assert_eq!(gain.get(), 2.5);
    }

    #[test]
    fn an_output_change_is_counted_once() {
        let before = output_changes();
        set_output(Some("Test Headset".to_string()));
        set_output(Some("Test Headset".to_string()));
        let (changes, device) = output();
        assert_eq!(device.as_deref(), Some("Test Headset"));
        assert_eq!(changes, before + 1);
        set_output(None);
    }
}
