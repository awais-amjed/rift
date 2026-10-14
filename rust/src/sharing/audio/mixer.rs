//! Mixing several applications' sound into one track.
//!
//! Each application arrives on its own record stream, in its own fragments,
//! and none of them is the clock: one can pause, quit or start late. So the
//! output is paced by the fullest lane. Once any lane holds a frame plus
//! [`SLACK`], a frame goes out, mixed from every lane that has caught up.
//! Applications playing to the same device share its clock and stay together.
//! One on another device drifts slowly, and when it runs short it sits out
//! until it has [`PRIME`] again. That costs it a few milliseconds every few
//! minutes, instead of a gap in every frame.
use super::NUM_CHANNELS;
use super::SAMPLE_RATE;
use std::collections::{HashMap, VecDeque};

/// Ten milliseconds of interleaved samples, the frame LiveKit takes.
pub(crate) const FRAME: usize = (SAMPLE_RATE as usize / 100) * NUM_CHANNELS as usize;
/// How far one application's fragments may arrive behind another's before it
/// runs short: a record stream hands over one fragment every 10 ms.
const SLACK: usize = 2 * FRAME;
/// What a lane that ran short needs again before it plays.
const PRIME: usize = 2 * FRAME;
/// The most a lane may hold. A stream that starts with a backlog would
/// otherwise put that backlog's delay on everything after it.
const MOST: usize = 10 * FRAME;

#[derive(Default)]
struct Lane {
    samples: VecDeque<i16>,
    /// Playing, rather than waiting for [`PRIME`] after running short.
    primed: bool,
}

/// Lanes of interleaved samples, keyed by whatever the platform names a
/// stream by, mixed a frame at a time.
#[derive(Default)]
pub(crate) struct Mixer {
    lanes: HashMap<u32, Lane>,
}

impl Mixer {
    pub(crate) fn push(&mut self, lane: u32, samples: &[i16]) {
        let lane = self.lanes.entry(lane).or_default();
        lane.samples.extend(samples);
        if lane.samples.len() > MOST {
            let excess = lane.samples.len() - (FRAME + SLACK);
            lane.samples.drain(..excess);
        }
        if lane.samples.len() >= PRIME {
            lane.primed = true;
        }
    }

    /// Forget a stream that ended. What it still held is dropped with it.
    pub(crate) fn remove(&mut self, lane: u32) {
        self.lanes.remove(&lane);
    }

    /// The next 10 ms, once some lane has enough for it.
    pub(crate) fn next_frame(&mut self) -> Option<Vec<i16>> {
        let fullest = self.lanes.values().map(|l| l.samples.len()).max()?;
        if fullest < FRAME + SLACK {
            return None;
        }
        let mut mixed = [0i32; FRAME];
        for lane in self.lanes.values_mut().filter(|l| l.primed) {
            let take = lane.samples.len().min(FRAME);
            for (sum, sample) in mixed.iter_mut().zip(lane.samples.drain(..take)) {
                *sum += sample as i32;
            }
            if take < FRAME {
                lane.primed = false;
            }
        }
        Some(
            mixed
                .iter()
                .map(|&sum| sum.clamp(i16::MIN as i32, i16::MAX as i32) as i16)
                .collect(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frames(mixer: &mut Mixer) -> Vec<Vec<i16>> {
        std::iter::from_fn(|| mixer.next_frame()).collect()
    }

    #[test]
    fn nothing_goes_out_until_a_lane_has_slack() {
        let mut mixer = Mixer::default();
        mixer.push(1, &[1; FRAME + SLACK - 2]);
        assert!(mixer.next_frame().is_none());
        mixer.push(1, &[1; 2]);
        assert_eq!(mixer.next_frame().unwrap(), vec![1; FRAME]);
    }

    #[test]
    fn two_lanes_add_up() {
        let mut mixer = Mixer::default();
        mixer.push(1, &[100; 3 * FRAME]);
        mixer.push(2, &[-30; 3 * FRAME]);
        assert_eq!(mixer.next_frame().unwrap(), vec![70; FRAME]);
    }

    #[test]
    fn loud_lanes_clip_instead_of_wrapping() {
        let mut mixer = Mixer::default();
        for lane in 1..=5 {
            let sample = if lane <= 2 { i16::MAX } else { i16::MIN };
            mixer.push(lane, &[sample; 4 * FRAME]);
        }
        assert_eq!(mixer.next_frame().unwrap(), vec![i16::MIN; FRAME]);
        mixer.remove(3);
        mixer.remove(4);
        mixer.remove(5);
        assert_eq!(mixer.next_frame().unwrap(), vec![i16::MAX; FRAME]);
    }

    #[test]
    fn a_paused_lane_does_not_hold_up_the_others() {
        let mut mixer = Mixer::default();
        mixer.push(1, &[5; PRIME]);
        mixer.push(2, &[7; 10 * FRAME]);
        let out = frames(&mut mixer);
        // Lane 2 plays down to its slack; lane 1 is in the first two frames.
        assert_eq!(out.len(), 8);
        assert_eq!(out[0], vec![12; FRAME]);
        assert_eq!(out[1], vec![12; FRAME]);
        assert_eq!(out[2], vec![7; FRAME]);
    }

    #[test]
    fn a_lane_that_ran_short_waits_to_prime_again() {
        let mut mixer = Mixer::default();
        mixer.push(1, &[1; PRIME + FRAME / 2]);
        mixer.push(2, &[2; 9 * FRAME]);
        let out = frames(&mut mixer);
        // Half a frame of lane 1, then silence from it.
        assert_eq!(out[2][..FRAME / 2], vec![3; FRAME / 2]);
        assert_eq!(out[2][FRAME / 2..], vec![2; FRAME / 2]);
        // A trickle below PRIME is held rather than played in scraps.
        mixer.push(1, &[1; FRAME]);
        mixer.push(2, &[2; 3 * FRAME]);
        assert_eq!(mixer.next_frame().unwrap(), vec![2; FRAME]);
        mixer.push(1, &[1; FRAME]);
        assert_eq!(mixer.next_frame().unwrap(), vec![3; FRAME]);
    }

    #[test]
    fn a_backlog_is_cut_to_the_slack() {
        let mut mixer = Mixer::default();
        mixer.push(1, &[1; 50 * FRAME]);
        assert_eq!(frames(&mut mixer).len(), 1);
    }

    #[test]
    fn a_removed_lane_stops_counting() {
        let mut mixer = Mixer::default();
        mixer.push(1, &[1; 5 * FRAME]);
        mixer.remove(1);
        assert!(mixer.next_frame().is_none());
    }
}
