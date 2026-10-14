//! The mic volume, applied to what the test reads, so the meter and the
//! playback answer to it as the call does. The call's own is in the runner's
//! filter (`native/noise_filter`), which the test does not go through; this
//! is the same gain and the same limiter.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU32, Ordering};

/// The loudest a boosted voice may come out: 2 dB under full scale, as the
/// call's ceiling is (why is there).
const CEILING: f32 = 0.79 * i16::MAX as f32;

/// How fast the limiter lets go once a loud syllable has passed.
const RELEASE_SECONDS: f32 = 0.1;

/// How far ahead the limiter looks: the gain starts down this long before a
/// peak, so it is never pinned to the ceiling for the peak itself, which is
/// heard as a fuzz on loud vowels.
const LOOK_AHEAD_SECONDS: f32 = 0.0015;

/// How long the limiter holds the gain down after a peak before letting go:
/// longer than one pitch period of a low voice, or the gain would rise and
/// fall with every cycle of it, which is distortion of its own.
const HOLD_SECONDS: f32 = 0.02;

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

/// One test's limiter.
///
/// For each sample, the gain it needs to stay under [`CEILING`] (1 when it
/// does already); the least of those over the look-ahead and the hold; that
/// let back up towards 1 over [`RELEASE_SECONDS`]; and the mean of the last
/// look-ahead's worth of it applied to the sample that look-ahead ago. Every
/// value in that mean comes from a window holding the sample it is applied to,
/// so none is more than that sample needs, and the ceiling holds; the mean
/// makes the gain glide down over the look-ahead instead of stepping.
///
/// The voice comes out the look-ahead late at every volume, 1 included, so
/// that dragging the slider across 100% never makes it jump.
pub(super) struct Boost {
    /// Samples looked ahead; the voice comes out one fewer late.
    look_ahead: usize,
    /// Look-ahead and hold together: how far back the least gain is taken.
    window: u64,
    release: f32,
    /// Samples seen.
    count: u64,
    /// The last look-ahead's boosted samples, oldest next to be written.
    delayed: Vec<f32>,
    /// The last look-ahead's held gains, and their sum.
    held: Vec<f32>,
    held_sum: f64,
    /// The gain held after the latest sample.
    hold: f32,
    /// The gains needed over the window that are less than every one needed
    /// after them, by sample number: the least is at the front.
    least: VecDeque<(u64, f32)>,
}

impl Boost {
    pub(super) fn new(sample_rate: u32) -> Self {
        let rate = sample_rate as f32;
        let look_ahead = ((LOOK_AHEAD_SECONDS * rate).round() as usize).max(1);
        let window = look_ahead + (HOLD_SECONDS * rate).round() as usize;
        Self {
            look_ahead,
            window: window as u64,
            release: (-1.0 / (RELEASE_SECONDS * rate)).exp(),
            count: 0,
            delayed: vec![0.0; look_ahead],
            held: vec![1.0; look_ahead],
            held_sum: look_ahead as f64,
            hold: 1.0,
            least: VecDeque::with_capacity(window),
        }
    }

    /// Applies the mic volume to `samples` as they stand.
    pub(super) fn apply(&mut self, samples: &mut [i16]) {
        self.apply_gain(samples, gain());
    }

    /// Below or at 1 the samples are only scaled, late by the look-ahead
    /// like the rest; above it they are limited as well.
    fn apply_gain(&mut self, samples: &mut [i16], gain: f32) {
        for s in samples.iter_mut() {
            *s = self.next(f32::from(*s) * gain, gain > 1.0).round() as i16;
        }
    }

    /// Takes one boosted sample and gives back the one a look-ahead ago.
    fn next(&mut self, boosted: f32, limit: bool) -> f32 {
        let needs = if limit && boosted.abs() > CEILING {
            CEILING / boosted.abs()
        } else {
            1.0
        };
        let n = self.count;
        self.count += 1;
        // Out of the window first, so the queue never holds more than it.
        while self
            .least
            .front()
            .is_some_and(|&(i, _)| i + self.window <= n)
        {
            self.least.pop_front();
        }
        while self.least.back().is_some_and(|&(_, g)| g >= needs) {
            self.least.pop_back();
        }
        self.least.push_back((n, needs));
        let least = self.least.front().map_or(1.0, |&(_, g)| g);
        self.hold = least.min(1.0 - (1.0 - self.hold) * self.release);

        let slot = (n % self.look_ahead as u64) as usize;
        self.held_sum += f64::from(self.hold) - f64::from(self.held[slot]);
        self.held[slot] = self.hold;
        if slot == 0 {
            // Summed afresh once a look-ahead, so rounding never builds up.
            self.held_sum = self.held.iter().map(|&h| f64::from(h)).sum();
        }
        self.delayed[slot] = boosted;
        let oldest = self.delayed[(slot + 1) % self.look_ahead];
        oldest * (self.held_sum / self.look_ahead as f64) as f32
    }

    /// How many samples late the voice comes out.
    #[cfg(test)]
    fn delay(&self) -> usize {
        self.look_ahead - 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `samples` through a fresh limiter at `rate`, with enough silence after
    /// for the last of them to come out, and the output lined up with them.
    fn through(samples: &[i16], gain: f32, rate: u32) -> Vec<i16> {
        let mut boost = Boost::new(rate);
        let delay = boost.delay();
        let mut out: Vec<i16> = samples.to_vec();
        out.extend(std::iter::repeat_n(0, delay));
        boost.apply_gain(&mut out, gain);
        out.split_off(delay)
    }

    /// A sine at `hz` and `level` (of full scale), `seconds` long.
    fn sine(hz: f32, level: f32, seconds: f32, rate: u32) -> Vec<i16> {
        (0..(seconds * rate as f32) as usize)
            .map(|i| {
                let t = i as f32 / rate as f32;
                (level * f32::from(i16::MAX) * (std::f32::consts::TAU * hz * t).sin()).round()
                    as i16
            })
            .collect()
    }

    #[test]
    fn one_leaves_the_voice_alone_only_late() {
        let samples = vec![100, -32768, 32767, 5, -5];
        let mut boost = Boost::new(48_000);
        let delay = boost.delay();
        assert_eq!(delay, 71);
        let mut out = samples.clone();
        out.extend(std::iter::repeat_n(0, delay));
        boost.apply_gain(&mut out, 1.0);
        assert!(out[..delay].iter().all(|&s| s == 0));
        assert_eq!(out[delay..], samples[..]);
    }

    #[test]
    fn below_one_scales() {
        assert_eq!(through(&[1000, -1000], 0.5, 16_000), vec![500, -500]);
    }

    #[test]
    fn a_quiet_voice_is_boosted_in_full() {
        assert_eq!(
            through(&[1000, -2000, 500], 4.0, 16_000),
            vec![4000, -8000, 2000]
        );
    }

    #[test]
    fn a_loud_voice_is_held_under_the_ceiling_not_cut_flat() {
        // A 200 Hz sine near full scale, boosted four times over.
        let original: Vec<i16> = (0..1600)
            .map(|i| (30_000.0 * (i as f32 * 0.0785).sin()) as i16)
            .collect();
        let samples = through(&original, 4.0, 16_000);
        assert!(samples.iter().all(|s| f32::from(s.abs()) <= CEILING + 1.0));
        // Still the same wave, only quieter: the gain is steady across it.
        // Cut off flat, it would be 4 near the zero crossings and barely 1 at
        // the crests.
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
        assert!(high / low < 1.01, "gain swung from {low} to {high}");
    }

    #[test]
    fn a_loud_vowel_comes_out_clean() {
        // The old limiter, which took the gain down at once on each peak,
        // pinned 8% of these samples to the ceiling: what was left once the
        // tone was taken out was only 42 dB under it.
        let rate = 48_000;
        let samples = through(&sine(180.0, 0.7, 2.0, rate), 2.0, rate);
        let settled = &samples[rate as usize / 5..];
        assert!(settled.iter().all(|s| f32::from(s.abs()) <= CEILING + 1.0));
        let under = tone_to_rest_db(settled, 180.0, rate);
        assert!(
            under > 60.0,
            "the rest is only {under:.1} dB under the tone"
        );
    }

    /// How far under the tone at `hz` everything else in `samples` is, in dB.
    fn tone_to_rest_db(samples: &[i16], hz: f32, rate: u32) -> f64 {
        let w = std::f64::consts::TAU * f64::from(hz) / f64::from(rate);
        let (mut ss, mut cc, mut sc, mut ys, mut yc) = (0.0, 0.0, 0.0, 0.0, 0.0);
        for (i, &y) in samples.iter().enumerate() {
            let (s, c, y) = ((w * i as f64).sin(), (w * i as f64).cos(), f64::from(y));
            ss += s * s;
            cc += c * c;
            sc += s * c;
            ys += y * s;
            yc += y * c;
        }
        let det = ss * cc - sc * sc;
        let (a, b) = ((ys * cc - yc * sc) / det, (yc * ss - ys * sc) / det);
        let (mut tone, mut rest) = (0.0, 0.0);
        for (i, &y) in samples.iter().enumerate() {
            let fit = a * (w * i as f64).sin() + b * (w * i as f64).cos();
            tone += fit * fit;
            rest += (f64::from(y) - fit).powi(2);
        }
        10.0 * (tone / rest).log10()
    }

    #[test]
    fn a_sudden_shout_stays_under_the_ceiling() {
        let mut samples = vec![0i16; 4800];
        samples.extend(sine(300.0, 1.0, 0.2, 48_000));
        let out = through(&samples, 4.0, 48_000);
        assert!(out.iter().all(|s| f32::from(s.abs()) <= CEILING + 1.0));
    }

    #[test]
    fn the_gain_comes_back_after_a_peak() {
        let mut boost = Boost::new(16_000);
        boost.apply_gain(&mut [30_000], 4.0);
        // A second of quiet later, the quiet is boosted in full again.
        let mut quiet = vec![100; 16_000];
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
