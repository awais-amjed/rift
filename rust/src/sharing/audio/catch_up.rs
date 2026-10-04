//! Keeping shared sound close to live.
//!
//! LiveKit's source takes 10 ms out of its queue every 10 ms of the system
//! clock and plays silence when the queue is empty; nothing ever leaves it
//! early. So delay only ever grows. A stall of the capture plays as silence,
//! the backlog arrives behind it and is then played in full, late, for the rest
//! of the share. A sound card running a touch faster than the system clock
//! builds up a backlog by itself. Video always sends its newest frame, so the
//! picture stays live and the sound falls behind it. A viewer cannot correct
//! this: the delay is added before the sound is time-stamped.
//!
//! [`CatchUp`] tracks how far the sound handed over runs ahead of the clock,
//! plus how long a frame waited before it got here, and drops frames
//! beyond [`MAX_DELAY`]. That costs a few milliseconds of sound after a stall,
//! and once every few minutes on a drifting card, in place of a lag that never
//! goes away.
use std::time::{Duration, Instant};

/// How late sound may be by the time LiveKit would send it. Above the jitter of
/// a normal capture, which reads every 5–10 ms, and below the point where
/// sound behind the picture is noticeable.
pub(crate) const MAX_DELAY: Duration = Duration::from_millis(80);

#[derive(Debug, Default)]
pub(crate) struct CatchUp {
    /// When the sound already handed over runs out, if it does not already
    /// have; past that, the source is playing silence.
    queued_until: Option<Instant>,
}

impl CatchUp {
    /// Whether a frame `length` long, read from the device at `read_at`, should
    /// go out at `now`. A frame let through counts as queued from then on.
    pub(crate) fn admit(&mut self, read_at: Instant, length: Duration, now: Instant) -> bool {
        // Once the queue has run dry the source has filled the gap with
        // silence, so the next frame starts playing now, not where the last
        // one ended.
        let queued_until = self.queued_until.map_or(now, |until| until.max(now));
        let delay = now.saturating_duration_since(read_at) + (queued_until - now);
        if delay > MAX_DELAY {
            self.queued_until = Some(queued_until);
            return false;
        }
        self.queued_until = Some(queued_until + length);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEN_MS: Duration = Duration::from_millis(10);

    /// Feeds `frames` 10 ms frames read at `at`, handed over at `at`, and
    /// says how many went out.
    fn burst(catch_up: &mut CatchUp, frames: usize, at: Instant) -> usize {
        (0..frames)
            .filter(|_| catch_up.admit(at, TEN_MS, at))
            .count()
    }

    #[test]
    fn frames_arriving_in_time_all_go_out() {
        let start = Instant::now();
        let mut catch_up = CatchUp::default();
        let sent = (0..1000)
            .filter(|&i| {
                let at = start + TEN_MS * i;
                catch_up.admit(at, TEN_MS, at)
            })
            .count();
        assert_eq!(sent, 1000);
    }

    #[test]
    fn a_backlog_after_a_stall_is_cut_to_the_limit() {
        // A second's backlog arriving at once: what fits under the limit
        // plays, the rest does not.
        let mut catch_up = CatchUp::default();
        let sent = burst(&mut catch_up, 100, Instant::now());
        assert_eq!(sent, 9);
    }

    #[test]
    fn frames_that_waited_too_long_on_the_way_are_dropped() {
        let now = Instant::now();
        let mut catch_up = CatchUp::default();
        assert!(!catch_up.admit(now - Duration::from_millis(200), TEN_MS, now));
        assert!(catch_up.admit(now - Duration::from_millis(20), TEN_MS, now));
    }

    #[test]
    fn a_dry_queue_starts_again_from_now() {
        let start = Instant::now();
        let mut catch_up = CatchUp::default();
        assert_eq!(burst(&mut catch_up, 9, start), 9);
        // A second later the queue played out long ago; a full burst fits
        // again rather than counting from where the last one ended.
        assert_eq!(burst(&mut catch_up, 9, start + Duration::from_secs(1)), 9);
    }

    #[test]
    fn a_fast_sound_card_is_held_to_the_limit() {
        // 1% fast: 101 frames for every 100 the clock plays. Over a minute
        // that is 600 ms of extra sound; all but what fits the limit is dropped.
        let start = Instant::now();
        let mut catch_up = CatchUp::default();
        let period = TEN_MS * 100 / 101;
        let sent = (0..6060)
            .filter(|&i| {
                let at = start + period * i;
                catch_up.admit(at, TEN_MS, at)
            })
            .count();
        let played = 6000 + MAX_DELAY.as_millis() as usize / 10;
        assert!((played - 1..=played + 1).contains(&sent), "sent {sent}");
    }
}
