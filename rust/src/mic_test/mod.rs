//! Reading a microphone for the settings mic test, and playing it back. Why
//! it does not go through WebRTC is in `api::mic_test`.
//!
//! Running one test at a time and stopping it is the same everywhere; each
//! platform supplies `run`, which opens the device and reads it until told to
//! stop, writing what it reads to the output as it goes.

use crate::frb_generated::StreamSink;
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::Mutex;
use std::thread::{self, JoinHandle};

mod boost;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
use linux::run;
#[cfg(target_os = "windows")]
use windows::run;

pub(crate) use boost::set_gain;
use boost::Boost;

/// The meter's format (`micTapFormat` on the Dart side): mono 16-bit at
/// 16 kHz. The platform converts whatever the device runs at.
const SAMPLE_RATE: u32 = 16_000;

/// How far behind the voice its playback may fall on Linux, in samples: 60 ms.
/// Enough for a late wake not to run the output dry; short enough to hear
/// yourself as you speak rather than as an echo. Windows keeps its own count
/// (`windows::MAX_QUEUED_SAMPLES`).
#[cfg(target_os = "linux")]
const PLAYBACK_SAMPLES: usize = SAMPLE_RATE as usize * 60 / 1000;

/// Where the test plays the microphone back, so you hear what Rift hears.
pub(crate) struct Playback {
    /// The id WebRTC lists the output under, or None for the default — as
    /// the cues take it.
    pub device_id: Option<String>,
    /// 0 to 1.
    pub volume: f32,
}

/// The running test: how to stop it, and the thread to wait for.
static RUNNING: Mutex<Option<(Sender<()>, JoinHandle<()>)>> = Mutex::new(None);

pub(crate) fn start(
    device_id: Option<String>,
    playback: Option<Playback>,
    sink: StreamSink<Vec<i16>>,
) {
    // One test at a time; a new one replaces the old.
    stop();
    let (stop_tx, stop_rx) = mpsc::channel();
    let thread = thread::spawn(move || {
        if let Err(message) = run(device_id.as_deref(), playback.as_ref(), &sink, &stop_rx) {
            log::warn!("mic test: {message}");
            let _ = sink.add_error(message);
        }
    });
    *RUNNING.lock().unwrap() = Some((stop_tx, thread));
}

pub(crate) fn stop() {
    let running = RUNNING.lock().unwrap().take();
    if let Some((stop_tx, thread)) = running {
        let _ = stop_tx.send(());
        let _ = thread.join();
    }
}

/// Whether [`stop`] has been called, or the test that owned `stop` is gone.
fn stopped(stop: &Receiver<()>) -> bool {
    !matches!(stop.try_recv(), Err(TryRecvError::Empty))
}

/// What of `samples` to play when the output has `room` samples free, scaled
/// by `volume`. The rest is dropped rather than held for later: holding it
/// would add to the delay between speaking and hearing yourself, for good.
fn for_playback(samples: &[i16], room: usize, volume: f32) -> Vec<i16> {
    samples[..samples.len().min(room)]
        .iter()
        .map(|&s| crate::cue::scale(s, volume))
        .collect()
}

/// Little-endian 16-bit PCM as samples. A trailing odd byte is dropped.
fn samples_from_le_bytes(bytes: &[u8]) -> Vec<i16> {
    bytes
        .chunks_exact(2)
        .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn playback_takes_what_fits_scaled() {
        assert_eq!(for_playback(&[100, -100, 300], 2, 0.5), vec![50, -50]);
        assert_eq!(for_playback(&[100, -100], 8, 1.0), vec![100, -100]);
        assert!(for_playback(&[100], 0, 1.0).is_empty());
    }

    #[test]
    fn samples_are_little_endian_pairs() {
        assert_eq!(
            samples_from_le_bytes(&[0x01, 0x00, 0xff, 0x7f, 0x00, 0x80, 0x09]),
            vec![1, i16::MAX, i16::MIN]
        );
    }
}
