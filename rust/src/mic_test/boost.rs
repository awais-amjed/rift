//! The mic volume, applied to what the test reads, so the meter and the
//! playback answer to it as the call does. The call's own is in the runner's
//! filter (`native/noise_filter`), which the test does not go through; this
//! is the same gain and the same limiter.

use std::sync::atomic::{AtomicU32, Ordering};

/// The loudest a boosted voice may come out: 2 dB under full scale, as the
/// call's ceiling is (why is there).
const CEILING: f32 = 0.79 * i16::MAX as f32;

/// How fast the limiter lets go once a loud syllable has passed.
const RELEASE_SECONDS: f32 = 0.1;

/// The mic volume as a gain, as an `f32`'s bits so a drag on the slider
/// reaches a running test. 1 to begin with.
static GAIN: AtomicU32 = AtomicU32::new(0x3f80_0000);

pub(crate) fn set_gain(gain: f32) {
    let gain = if gain.is_finite() && gain > 0.0 {
        gain
    } else {
        1.0
    };
    GAIN.store(gain.to_bits(), Ordering::Relaxed);
}

fn gain() -> f32 {
    f32::from_bits(GAIN.load(Ordering::Relaxed))
}

/// One test's limiter: where the loudest recent peak was.
pub(super) struct Boost {
    envelope: f32,
    release: f32,
}

impl Boost {
    pub(super) fn new(sample_rate: u32) -> Self {
        Self {
            envelope: 0.0,
            release: (-1.0 / (RELEASE_SECONDS * sample_rate as f32)).exp(),
        }
    }

    /// Applies the mic volume to `samples` as they stand.
    pub(super) fn apply(&mut self, samples: &mut [i16]) {
        self.apply_gain(samples, gain());
    }

    /// Below 1 a plain scale. Above it, a voice that already peaks near full
    /// scale would be cut off flat, so the gain is taken down at once on a
    /// peak, enough to hold it under [`CEILING`], and given back over
    /// [`RELEASE_SECONDS`].
    fn apply_gain(&mut self, samples: &mut [i16], gain: f32) {
        if gain <= 1.0 {
            self.envelope = 0.0;
            if gain < 1.0 {
                for s in samples.iter_mut() {
                    *s = (f32::from(*s) * gain).round() as i16;
                }
            }
            return;
        }
        for s in samples.iter_mut() {
            let boosted = f32::from(*s) * gain;
            self.envelope = boosted.abs().max(self.envelope * self.release);
            let limited = if self.envelope > CEILING {
                boosted * (CEILING / self.envelope)
            } else {
                boosted
            };
            *s = limited.round() as i16;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_leaves_the_voice_alone() {
        let mut samples = vec![100, -32768, 32767];
        Boost::new(16_000).apply_gain(&mut samples, 1.0);
        assert_eq!(samples, vec![100, -32768, 32767]);
    }

    #[test]
    fn below_one_scales() {
        let mut samples = vec![1000, -1000];
        Boost::new(16_000).apply_gain(&mut samples, 0.5);
        assert_eq!(samples, vec![500, -500]);
    }

    #[test]
    fn a_quiet_voice_is_boosted_in_full() {
        let mut samples = vec![1000, -2000, 500];
        Boost::new(16_000).apply_gain(&mut samples, 4.0);
        assert_eq!(samples, vec![4000, -8000, 2000]);
    }

    #[test]
    fn a_loud_voice_is_held_under_the_ceiling_not_cut_flat() {
        let mut boost = Boost::new(16_000);
        // A 200 Hz sine near full scale, boosted four times over.
        let mut samples: Vec<i16> = (0..1600)
            .map(|i| (30_000.0 * (i as f32 * 0.0785).sin()) as i16)
            .collect();
        let original = samples.clone();
        boost.apply_gain(&mut samples, 4.0);
        assert!(samples.iter().all(|s| f32::from(s.abs()) <= CEILING + 1.0));
        // Still the same wave, only quieter: past the first peak the gain is
        // all but steady across it. Cut off flat, it would be 4 near the
        // zero crossings and barely 1 at the crests.
        let gains: Vec<f32> = original
            .iter()
            .zip(&samples)
            .skip(100)
            .filter(|(a, _)| a.abs() > 2000)
            .map(|(a, b)| f32::from(*b) / f32::from(*a))
            .collect();
        let (low, high) = gains
            .iter()
            .fold((f32::MAX, 0f32), |(l, h), g| (l.min(*g), h.max(*g)));
        assert!(high / low < 1.05, "gain swung from {low} to {high}");
    }

    #[test]
    fn the_gain_comes_back_after_a_peak() {
        let mut boost = Boost::new(16_000);
        boost.apply_gain(&mut [30_000], 4.0);
        // Half a second of quiet later, the quiet is boosted in full again.
        let mut quiet = vec![100; 8000];
        boost.apply_gain(&mut quiet, 4.0);
        assert_eq!(*quiet.last().unwrap(), 400);
    }

    #[test]
    fn a_nonsense_gain_is_one() {
        set_gain(f32::NAN);
        assert_eq!(gain(), 1.0);
        set_gain(2.0);
        assert_eq!(gain(), 2.0);
        set_gain(1.0);
    }
}
