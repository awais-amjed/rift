//! Rift's own sounds — a message chime, a call's cues, the ring — played on
//! the output device chosen in settings. Why they do not go through the
//! audio player the rest of the app uses is in `api::cue`.
//!
//! Each cue plays on a thread of its own, so a chime does not wait for a ring
//! to finish. Starting, turning down and stopping one is the same
//! everywhere; each platform supplies `run`, which opens the device and plays
//! a [`Cue`] until it ends or is stopped.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
use linux::run;
#[cfg(target_os = "windows")]
use windows::run;

/// How long a start waits to hear whether the device opened. Long enough for
/// a sound server that is slow to answer; short enough that a cue falling
/// back to the default device is still on time.
const OPEN_TIMEOUT: Duration = Duration::from_millis(1500);

/// 16-bit interleaved PCM and the position playing from.
pub(crate) struct Cue {
    samples: Vec<i16>,
    pub channels: u16,
    pub rate: u32,
    position: usize,
    looping: bool,
}

impl Cue {
    /// The cue in an MP3 file — how Rift's own sounds ship. Fails on bytes
    /// with no audio in them, or a stream that changes format part way.
    pub(crate) fn from_mp3(bytes: &[u8], looping: bool) -> Result<Cue, String> {
        let decoded = nanomp3::decode_all::<i16>(bytes);
        let channels = match decoded.channels {
            Some(nanomp3::Channels::Mono) => 1,
            Some(_) => 2,
            None => return Err("no audio in the cue".to_string()),
        };
        if decoded.samples.is_empty() || decoded.sample_rate == 0 {
            return Err("no audio in the cue".to_string());
        }
        Ok(Cue::new(
            decoded.samples,
            channels,
            decoded.sample_rate,
            looping,
        ))
    }

    /// How long one pass takes, in milliseconds.
    pub(crate) fn duration_ms(&self) -> u32 {
        let frames = self.samples.len() as u64 / u64::from(self.channels);
        (frames * 1000 / u64::from(self.rate.max(1))) as u32
    }

    pub(crate) fn new(samples: Vec<i16>, channels: u16, rate: u32, looping: bool) -> Cue {
        Cue {
            samples,
            channels: channels.max(1),
            rate,
            position: 0,
            looping,
        }
    }

    /// Writes the next whole frames into `out`, scaled by `volume`, and
    /// answers how many samples it wrote. Zero means the cue has ended; a
    /// looping one never ends.
    pub(crate) fn fill(&mut self, out: &mut [i16], volume: f32) -> usize {
        let channels = usize::from(self.channels);
        let room = out.len() / channels * channels;
        if self.samples.len() < channels {
            return 0;
        }
        let mut written = 0;
        while written < room {
            if self.position >= self.samples.len() {
                if !self.looping {
                    break;
                }
                self.position = 0;
            }
            let take = (room - written).min(self.samples.len() - self.position);
            for (to, from) in out[written..written + take]
                .iter_mut()
                .zip(&self.samples[self.position..self.position + take])
            {
                *to = scale(*from, volume);
            }
            written += take;
            self.position += take;
        }
        written
    }
}

pub(crate) fn scale(sample: i16, volume: f32) -> i16 {
    (f32::from(sample) * volume.clamp(0.0, 1.0)).round() as i16
}

/// What the caller can change while a cue plays.
pub(crate) struct Controls {
    stop: AtomicBool,
    /// An `f32`'s bits, so a drag on a slider reaches the playing cue.
    volume: AtomicU32,
}

impl Controls {
    pub(crate) fn stopped(&self) -> bool {
        self.stop.load(Ordering::Relaxed)
    }

    pub(crate) fn volume(&self) -> f32 {
        f32::from_bits(self.volume.load(Ordering::Relaxed))
    }
}

static NEXT_ID: AtomicU32 = AtomicU32::new(1);
static PLAYING: Mutex<Option<HashMap<u32, Arc<Controls>>>> = Mutex::new(None);

/// Starts `cue` on `device_id` — the id WebRTC lists the output under, or
/// `None` for the default — and answers its id once the device has opened,
/// or why it would not.
pub(crate) fn play(device_id: Option<String>, mut cue: Cue, volume: f32) -> Result<u32, String> {
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let controls = Arc::new(Controls {
        stop: AtomicBool::new(false),
        volume: AtomicU32::new(volume.to_bits()),
    });
    PLAYING
        .lock()
        .unwrap()
        .get_or_insert_with(HashMap::new)
        .insert(id, Arc::clone(&controls));

    let (opened_tx, opened_rx) = mpsc::channel();
    thread::spawn(move || {
        let result = run(device_id.as_deref(), &mut cue, &controls, &opened_tx);
        if let Err(message) = &result {
            log::warn!("cue: {message}");
            let _ = opened_tx.send(Err(message.clone()));
        }
        forget(id);
    });
    match opened_rx.recv_timeout(OPEN_TIMEOUT) {
        Ok(Ok(())) => Ok(id),
        Ok(Err(message)) => Err(message),
        Err(_) => {
            stop(id);
            Err("the output device did not open in time".to_string())
        }
    }
}

pub(crate) fn set_volume(id: u32, volume: f32) {
    if let Some(controls) = controls_of(id) {
        controls.volume.store(volume.to_bits(), Ordering::Relaxed);
    }
}

/// Stops the cue, if it is still playing. Does not wait for its thread.
pub(crate) fn stop(id: u32) {
    if let Some(controls) = controls_of(id) {
        controls.stop.store(true, Ordering::Relaxed);
    }
}

fn controls_of(id: u32) -> Option<Arc<Controls>> {
    PLAYING
        .lock()
        .unwrap()
        .as_ref()
        .and_then(|playing| playing.get(&id).cloned())
}

fn forget(id: u32) {
    if let Some(playing) = PLAYING.lock().unwrap().as_mut() {
        playing.remove(&id);
    }
}

/// Interleaved samples as little-endian bytes, which both platforms take.
pub(crate) fn le_bytes(samples: &[i16]) -> Vec<u8> {
    samples.iter().flat_map(|s| s.to_le_bytes()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plays_once_through_in_whole_frames() {
        let mut cue = Cue::new(vec![1, 2, 3, 4, 5, 6], 2, 48_000, false);
        let mut out = [0i16; 5];
        // Five slots hold two whole stereo frames, not two and a half.
        assert_eq!(cue.fill(&mut out, 1.0), 4);
        assert_eq!(&out[..4], &[1, 2, 3, 4]);
        assert_eq!(cue.fill(&mut out, 1.0), 2);
        assert_eq!(&out[..2], &[5, 6]);
        assert_eq!(cue.fill(&mut out, 1.0), 0);
    }

    #[test]
    fn a_loop_starts_again_and_never_ends() {
        let mut cue = Cue::new(vec![1, 2, 3], 1, 48_000, true);
        let mut out = [0i16; 7];
        assert_eq!(cue.fill(&mut out, 1.0), 7);
        assert_eq!(out, [1, 2, 3, 1, 2, 3, 1]);
        assert_eq!(cue.fill(&mut out[..2], 1.0), 2);
        assert_eq!(&out[..2], &[2, 3]);
    }

    #[test]
    fn volume_scales_and_is_clamped() {
        let mut cue = Cue::new(vec![1000, -1000, i16::MAX], 1, 48_000, false);
        let mut out = [0i16; 3];
        cue.fill(&mut out, 0.5);
        assert_eq!(out, [500, -500, 16384]);
        let mut loud = Cue::new(vec![i16::MAX], 1, 48_000, false);
        loud.fill(&mut out, 4.0);
        assert_eq!(out[0], i16::MAX);
    }

    #[test]
    fn nothing_to_play_ends_at_once() {
        let mut cue = Cue::new(Vec::new(), 2, 48_000, true);
        assert_eq!(cue.fill(&mut [0i16; 4], 1.0), 0);
    }

    #[test]
    fn decodes_the_sounds_rift_ships() {
        let ptt = Cue::from_mp3(include_bytes!("../../../assets/audio/ptt_on.mp3"), false).unwrap();
        assert_eq!((ptt.channels, ptt.rate), (1, 44_100));
        assert_eq!(ptt.duration_ms(), 160);
        let join = Cue::from_mp3(include_bytes!("../../../assets/audio/join.mp3"), false).unwrap();
        assert_eq!((join.channels, join.rate), (2, 44_100));
        assert_eq!(join.duration_ms(), 2089);
    }

    #[test]
    fn every_sound_rift_ships_decodes() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/audio");
        let mut seen = 0;
        for entry in std::fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().is_some_and(|e| e == "mp3") {
                let cue = Cue::from_mp3(&std::fs::read(&path).unwrap(), false);
                assert!(cue.is_ok(), "{}", path.display());
                seen += 1;
            }
        }
        assert!(seen > 0);
    }

    #[test]
    fn refuses_what_is_not_mp3() {
        assert!(Cue::from_mp3(b"not an mp3 at all", false).is_err());
        assert!(Cue::from_mp3(&[], true).is_err());
    }

    #[test]
    fn bytes_are_little_endian() {
        assert_eq!(le_bytes(&[1, -2]), vec![0x01, 0x00, 0xfe, 0xff]);
    }
}
