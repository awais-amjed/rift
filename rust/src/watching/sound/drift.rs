//! Keeps a share's sound level with the output it plays on.
//!
//! The sound comes off libwebrtc's clock, the system's, and the output plays
//! it on its own, and the two never quite agree. Left alone, the output either
//! runs dry, which is a gap in the sound (10 ms every 100 s on Linux, at 100
//! parts per million), or holds more and more, which puts the sound further
//! behind its picture for as long as the share is watched.
//!
//! So what the output holds is watched, and when it wanders too far from
//! where it settled, a frame is stretched or squeezed by one left-and-right
//! pair. Across the whole frame, not at one place: a pair simply cut out of a
//! 1 kHz tone splatters 32 dB below it, and spread over 8 ms, 41 dB below
//! (14 kHz: 10 and 25 dB). At one pair a frame, the most this does, the pitch
//! moves by 0.2%, under what an ear can tell.

use super::{CHANNELS, SAMPLE_RATE};
use std::borrow::Cow;

const PAIR: usize = CHANNELS as usize;
/// Samples in a millisecond.
const MS: f32 = (SAMPLE_RATE * CHANNELS) as f32 / 1000.0;

/// Frames to find where the output settles: 2 s. A frame is 10 ms.
const SETTLING_FRAMES: u32 = 200;

/// How much of each reading goes into the level: one second's worth. An output
/// empties in gulps, so a single reading says little.
const SMOOTHING: f32 = 0.01;

/// How far the level may wander from where it settled, each way: 8 ms, more
/// than half of a usual gulp, so that an output in step changes nothing.
const BAND: f32 = 8.0 * MS;

/// Frames between lines in the log: a minute.
const REPORT_FRAMES: u32 = 6000;

pub(super) struct Drift {
    /// Where the level must stay under.
    most: f32,
    level: Option<f32>,
    /// Where it settled, once it has.
    target: Option<f32>,
    settling: u32,
    frames: u32,
    taken: u32,
    added: u32,
    lowest: usize,
    highest: usize,
}

impl Drift {
    /// For an output that should hold under `most` samples.
    pub(super) fn new(most: usize) -> Drift {
        Drift {
            most: most as f32,
            level: None,
            target: None,
            settling: SETTLING_FRAMES,
            frames: 0,
            taken: 0,
            added: 0,
            lowest: usize::MAX,
            highest: 0,
        }
    }

    /// What to play of `frame` while the output holds `queued` samples.
    pub(super) fn adjust<'a>(&mut self, frame: &'a [i16], queued: usize) -> Cow<'a, [i16]> {
        if queued == 0 {
            // Ran dry, or has only just begun. What goes in next is what this
            // output turned out to need, so it is not taken back out.
            self.level = None;
            self.target = None;
            self.settling = SETTLING_FRAMES;
            return Cow::Borrowed(frame);
        }
        let reading = queued as f32;
        let level = self
            .level
            .map_or(reading, |level| level + (reading - level) * SMOOTHING);
        self.level = Some(level);
        let Some(target) = self.target else {
            self.settling = self.settling.saturating_sub(1);
            if self.settling == 0 {
                self.target = Some(level.min(self.most - BAND - MS));
            }
            return Cow::Borrowed(frame);
        };
        self.lowest = self.lowest.min(queued);
        self.highest = self.highest.max(queued);
        self.report(level, target);
        let pairs = frame.len() / PAIR;
        if pairs < 2 {
            return Cow::Borrowed(frame);
        }
        if level > target + BAND {
            self.taken += 1;
            Cow::Owned(stretched(frame, pairs - 1))
        } else if level < target - BAND {
            self.added += 1;
            Cow::Owned(stretched(frame, pairs + 1))
        } else {
            Cow::Borrowed(frame)
        }
    }

    fn report(&mut self, level: f32, target: f32) {
        self.frames += 1;
        if self.frames < REPORT_FRAMES {
            return;
        }
        log::info!(
            "watching: the output holds {:.0} ms of the sound (settled at {:.0}, read {:.0} to {:.0}); pairs in the last minute: {} taken, {} added",
            level / MS,
            target / MS,
            self.lowest as f32 / MS,
            self.highest as f32 / MS,
            self.taken,
            self.added
        );
        self.lowest = usize::MAX;
        self.highest = 0;
        self.frames = 0;
        self.taken = 0;
        self.added = 0;
    }
}

/// The interleaved stereo `frame` read across at an even pace into `pairs`
/// left-and-right pairs, starting on its first.
fn stretched(frame: &[i16], pairs: usize) -> Vec<i16> {
    let had = frame.len() / PAIR;
    let mut out = Vec::with_capacity(pairs * PAIR);
    for at in 0..pairs {
        let from = at * had / pairs;
        let part = (at * had % pairs) as f32 / pairs as f32;
        let next = (from + 1).min(had - 1);
        for channel in 0..PAIR {
            let this = f32::from(frame[from * PAIR + channel]);
            let then = f32::from(frame[next * PAIR + channel]);
            out.push((this + (then - this) * part).round() as i16);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const FRAME_PAIRS: usize = SAMPLE_RATE as usize / 100;
    const FRAME: usize = FRAME_PAIRS * PAIR;
    const MS: usize = FRAME / 10;
    /// Windows' hold, less a frame to fit and a gulp to wait for.
    const FULL: usize = 40 * MS;

    fn sine(hz: f64, pairs: usize) -> Vec<i16> {
        (0..pairs)
            .flat_map(|i| {
                let at = i as f64 * hz * std::f64::consts::TAU / f64::from(SAMPLE_RATE);
                let left = (at.sin() * 10_000.0) as i16;
                [left, -left]
            })
            .collect()
    }

    fn biggest_step(samples: &[i16]) -> i32 {
        samples
            .chunks(PAIR)
            .zip(samples.chunks(PAIR).skip(1))
            .map(|(a, b)| (i32::from(a[0]) - i32::from(b[0])).abs())
            .max()
            .unwrap_or(0)
    }

    /// An output emptied `gulp` samples at a time, on a clock `ppm` fast (or
    /// slow, when negative) against the 10 ms the feed runs on, for `minutes`,
    /// starting with `start` held.
    struct Run {
        lowest: usize,
        highest: usize,
        changed: usize,
    }

    fn run_against(ppm: f64, gulp: usize, start: usize, minutes: usize) -> Run {
        let mut drift = Drift::new(FULL);
        let frame = vec![0; FRAME];
        let gulp_every = gulp as f64 / FRAME as f64 * 10.0 / (1.0 + ppm / 1e6);
        let frames = minutes * 6000;
        let (mut held, mut next_gulp) = (start as i64, gulp_every);
        let (mut lowest, mut highest, mut changed) = (usize::MAX, 0, 0);
        // The first seconds settle, and don't count.
        let settled = 500;
        for n in 0..frames {
            let now = n as f64 * 10.0;
            while next_gulp <= now {
                held = (held - gulp as i64).max(0);
                next_gulp += gulp_every;
            }
            let written = drift.adjust(&frame, held as usize).len();
            if written != FRAME {
                changed += 1;
            }
            if n >= settled {
                lowest = lowest.min(held as usize);
                highest = highest.max(held as usize);
            }
            held += written as i64;
        }
        Run {
            lowest,
            highest,
            changed,
        }
    }

    #[test]
    fn an_output_in_step_changes_nothing() {
        let run = run_against(0.0, FRAME, 30 * MS, 10);
        assert_eq!(run.changed, 0);
    }

    #[test]
    fn a_slow_output_does_not_fill_up() {
        // 200 ppm slow: 72 ms over the ten minutes if nothing is done.
        let run = run_against(-200.0, FRAME, 40 * MS, 10);
        assert!(run.highest < 55 * MS, "held up to {}", run.highest / MS);
        assert!(run.changed > 1000, "changed {} frames", run.changed);
    }

    #[test]
    fn a_fast_output_does_not_run_dry() {
        // 200 ppm fast: dry after about three minutes if nothing is done.
        let run = run_against(200.0, FRAME, 40 * MS, 10);
        assert!(run.lowest > 10 * MS, "held down to {}", run.lowest / MS);
        assert!(run.changed > 1000, "changed {} frames", run.changed);
    }

    #[test]
    fn it_keeps_up_with_a_clock_far_out() {
        for ppm in [-1500.0, 1500.0] {
            let run = run_against(ppm, FRAME, 40 * MS, 2);
            assert!(run.lowest > 10 * MS, "{ppm}: down to {}", run.lowest / MS);
            assert!(run.highest < 55 * MS, "{ppm}: up to {}", run.highest / MS);
        }
    }

    #[test]
    fn an_output_that_empties_in_big_gulps_is_still_held() {
        for ppm in [-300.0, 50.0, 300.0] {
            // Its readings swing by a gulp; what matters is that the swing
            // stays where it is, instead of creeping up or running dry.
            let run = run_against(ppm, 3 * FRAME, 30 * MS, 10);
            assert!(run.lowest > 0, "{ppm}: ran dry");
            assert!(run.highest < 75 * MS, "{ppm}: up to {}", run.highest / MS);
        }
    }

    #[test]
    fn nothing_changes_while_it_settles() {
        let mut drift = Drift::new(FULL);
        let frame = vec![0; FRAME];
        for _ in 0..100 {
            assert_eq!(drift.adjust(&frame, FULL).len(), FRAME);
        }
    }

    /// A drift settled at `level`, with `too`'s reading then held until it acts.
    fn slipped(level: usize, too: usize, frame: &[i16]) -> Vec<i16> {
        let mut drift = Drift::new(FULL);
        let silence = vec![0; FRAME];
        for _ in 0..1000 {
            drift.adjust(&silence, level);
        }
        for _ in 0..2000 {
            let written = drift.adjust(frame, too);
            if written.len() != frame.len() {
                return written.into_owned();
            }
        }
        panic!("it never acted");
    }

    #[test]
    fn too_much_held_takes_one_pair_out() {
        let written = slipped(30 * MS, 50 * MS, &sine(440.0, FRAME_PAIRS));
        assert_eq!(written.len(), FRAME - PAIR);
    }

    #[test]
    fn too_little_held_puts_one_pair_in() {
        let written = slipped(30 * MS, 10 * MS, &sine(440.0, FRAME_PAIRS));
        assert_eq!(written.len(), FRAME + PAIR);
    }

    #[test]
    fn left_stays_left() {
        for too in [10 * MS, 50 * MS] {
            let written = slipped(30 * MS, too, &sine(440.0, FRAME_PAIRS));
            for pair in written.chunks(PAIR) {
                assert!(
                    (i32::from(pair[0]) + i32::from(pair[1])).abs() <= 1,
                    "{pair:?}"
                );
            }
        }
    }

    #[test]
    fn a_change_has_no_click() {
        // A pair simply cut out of a 1 kHz sine doubles its biggest step, and
        // that's the click.
        let frame = sine(1000.0, FRAME_PAIRS);
        let clean = biggest_step(&frame);
        for too in [10 * MS, 50 * MS] {
            let step = biggest_step(&slipped(30 * MS, too, &frame));
            assert!(step * 100 <= clean * 102, "{step} against {clean}");
        }
    }

    #[test]
    fn a_change_starts_and_ends_on_the_frame() {
        let frame = sine(1000.0, FRAME_PAIRS);
        for too in [10 * MS, 50 * MS] {
            let written = slipped(30 * MS, too, &frame);
            assert_eq!(written[0], frame[0]);
            let (last, tail) = (written.len() - PAIR, frame.len() - PAIR);
            assert!((i32::from(written[last]) - i32::from(frame[tail])).abs() <= 200);
        }
    }

    #[test]
    fn a_frame_too_short_to_change_is_left_alone() {
        let mut drift = Drift::new(FULL);
        for _ in 0..1000 {
            drift.adjust(&[], 30 * MS);
        }
        assert_eq!(drift.adjust(&[1, 2], 55 * MS).len(), 2);
    }

    #[test]
    fn settling_too_near_full_is_brought_down() {
        // Held at 58 ms from the start: a frame would not fit.
        let mut drift = Drift::new(FULL);
        let frame = vec![0; FRAME];
        let mut took = 0;
        for _ in 0..1000 {
            if drift.adjust(&frame, 58 * MS).len() < FRAME {
                took += 1;
            }
        }
        assert!(took > 0);
    }

    #[test]
    fn running_dry_settles_again() {
        let mut drift = Drift::new(FULL);
        let frame = vec![0; FRAME];
        for _ in 0..1000 {
            drift.adjust(&frame, 10 * MS);
        }
        // The cushion goes in and the output now holds more, for good: that
        // is what it needed, and it is not taken back out.
        drift.adjust(&frame, 0);
        for _ in 0..3000 {
            assert_eq!(drift.adjust(&frame, 30 * MS).len(), FRAME);
        }
    }
}
