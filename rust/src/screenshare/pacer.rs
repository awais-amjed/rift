//! Which pictures go on, at the share's rate. A compositor only sends a picture
//! when the source changes, at a refresh of the screen, so what arrives seldom
//! lines up with the rate. Each capturer therefore asks its compositor for
//! twice the rate and paces here: asked for the rate itself, a 165 Hz screen
//! gave every third refresh on Windows (55 fps of 60), and every other one on
//! GNOME (82 of 120, Nov 3 2026), whose screencast skips a refresh that comes
//! sooner than the rate allows and waits for the next.
use super::latest::Taker;
use std::time::{Duration, Instant};

/// Half a picture's time of slack keeps a source just above the share's rate
/// from beating against it (a 62 Hz picture at 60 fps came through at 50,
/// Nov 1 2026), and the time it is due moves on by a whole picture, so the
/// average is still the share's.
pub(crate) struct Pacer {
    due: Option<Instant>,
}

impl Pacer {
    pub(crate) fn new() -> Self {
        Self { due: None }
    }

    /// How long a picture at `now` must wait before it may go on: zero once
    /// it may.
    pub(crate) fn wait(&self, now: Instant, fps: u32) -> Duration {
        let interval = interval(fps);
        match self.due {
            Some(due) if now + interval / 2 < due => due - interval / 2 - now,
            _ => Duration::ZERO,
        }
    }

    /// Whether a picture at `now` goes on, moving the time the next is due
    /// when it does.
    pub(crate) fn admits(&mut self, now: Instant, fps: u32) -> bool {
        if !self.wait(now, fps).is_zero() {
            return false;
        }
        let interval = interval(fps);
        let next = self.due.unwrap_or(now) + interval;
        // Never from long ago, or a pause would be made up in a burst.
        self.due = Some(if next <= now { now + interval } else { next });
        true
    }

    /// `picture`, held until it may go on, or the newest that came while it
    /// waited: dropping one that came too early would leave a screen that
    /// then stood still showing the picture before it. `None` once nothing
    /// more will come.
    pub(crate) fn hold<T>(
        &mut self,
        pictures: &Taker<T>,
        mut picture: T,
        fps: &dyn Fn() -> u32,
    ) -> Option<T> {
        loop {
            let wait = self.wait(Instant::now(), fps());
            if wait.is_zero() {
                break;
            }
            match pictures.take_timeout(wait) {
                Some(newer) => picture = newer,
                None if pictures.closed() => return None,
                None => {}
            }
        }
        self.admits(Instant::now(), fps());
        Some(picture)
    }
}

fn interval(fps: u32) -> Duration {
    Duration::from_secs_f64(1.0 / f64::from(fps.max(1)))
}

/// The rate a capturer asks its compositor for, to pace down to `fps`
/// ([`Pacer`]).
pub(crate) fn asked_rate(fps: u32) -> u32 {
    fps.max(1).saturating_mul(2)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::screenshare::latest;
    use std::thread;

    /// Counts what a screen refreshing at `hz` gets through a pacer at `fps`.
    fn admitted(hz: f64, fps: u32) -> u32 {
        let start = Instant::now();
        let mut pacer = Pacer::new();
        (0..(hz as u32 * 10))
            .filter(|tick| {
                pacer.admits(start + Duration::from_secs_f64(f64::from(*tick) / hz), fps)
            })
            .count() as u32
    }

    #[test]
    fn a_faster_screen_is_paced_to_the_share() {
        // Ten seconds of each: within a picture or two of the share's rate, even
        // where the screen's does not divide into it.
        assert!(admitted(165.0, 60).abs_diff(600) <= 2);
        assert!(admitted(240.0, 60).abs_diff(600) <= 2);
        assert!(admitted(165.0, 120).abs_diff(1200) <= 2);
        assert!(admitted(144.0, 120).abs_diff(1200) <= 2);
        assert!(admitted(240.0, 120).abs_diff(1200) <= 2);
    }

    #[test]
    fn a_source_just_above_the_rate_does_not_beat_against_it() {
        assert!(admitted(62.0, 60).abs_diff(600) <= 2);
    }

    #[test]
    fn a_slower_screen_is_all_let_through() {
        assert_eq!(admitted(60.0, 120), 600);
    }

    #[test]
    fn a_pause_is_not_made_up_in_a_burst() {
        let start = Instant::now();
        let mut pacer = Pacer::new();
        assert!(pacer.admits(start, 60));
        let later = start + Duration::from_secs(5);
        assert!(pacer.admits(later, 60));
        assert!(!pacer.admits(later + Duration::from_millis(2), 60));
    }

    #[test]
    fn a_picture_that_comes_too_early_waits_for_its_time() {
        let start = Instant::now();
        let mut pacer = Pacer::new();
        assert!(pacer.admits(start, 120));
        // Due at 8.3 ms, with half a picture's slack: from 4.2 ms on.
        assert!(pacer.wait(start + Duration::from_millis(5), 120).is_zero());
        let left = pacer.wait(start + Duration::from_millis(2), 120);
        assert!(
            left > Duration::from_millis(2) && left < Duration::from_millis(3),
            "{left:?}"
        );
    }

    #[test]
    fn an_early_picture_is_held_not_dropped() {
        let (put, take) = latest::channel::<u32>();
        let mut pacer = Pacer::new();
        assert!(pacer.admits(Instant::now(), 10));
        // The last change of a screen that then stands still.
        let before = Instant::now();
        assert_eq!(pacer.hold(&take, 1, &|| 10), Some(1));
        // Held until half a picture before its time, 50 ms at 10 fps.
        assert!(
            before.elapsed() >= Duration::from_millis(40),
            "{:?}",
            before.elapsed()
        );
        drop(put);
    }

    #[test]
    fn a_newer_picture_replaces_the_one_held() {
        let (put, take) = latest::channel::<u32>();
        let mut pacer = Pacer::new();
        assert!(pacer.admits(Instant::now(), 10));
        let putter = thread::spawn(move || {
            thread::sleep(Duration::from_millis(10));
            put.put(2);
            put
        });
        assert_eq!(pacer.hold(&take, 1, &|| 10), Some(2));
        drop(putter.join().unwrap());
    }

    #[test]
    fn a_closed_stream_ends_the_hold() {
        let (put, take) = latest::channel::<u32>();
        let mut pacer = Pacer::new();
        assert!(pacer.admits(Instant::now(), 10));
        drop(put);
        assert_eq!(pacer.hold(&take, 1, &|| 10), None);
    }

    #[test]
    fn the_compositor_is_asked_for_twice_the_rate() {
        assert_eq!(asked_rate(120), 240);
        assert_eq!(asked_rate(0), 2);
    }
}
