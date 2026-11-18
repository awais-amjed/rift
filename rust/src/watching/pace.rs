//! How evenly a watched share's pictures arrive, said in the log once a minute
//! beside the sound's line (`sound::drift`).
//!
//! A report of a stuttering share had the sharer's log, which says what it left
//! out to fit its connection, and nothing from the watcher about what came.
//! This line is that half: pictures that came and were drawn, waits between
//! them a viewer sees as a jerk, and pictures replaced before the window drew
//! them, which is the watcher's own window falling behind rather than the
//! network.
use std::time::{Duration, Instant};

/// How often the line is written while pictures keep coming.
const REPORT_EVERY: Duration = Duration::from_secs(60);
/// A wait between pictures this long shows: six pictures missed at 60 fps.
const GAP: Duration = Duration::from_millis(100);
/// A wait this long is the picture turned off or the share paused, not a
/// stutter: the stretch so far is reported and a new one begins.
const PAUSE: Duration = Duration::from_secs(3);
/// A stretch shorter than this, ended by a pause or the watch closing, says
/// too little to be worth a line.
const LEAST_REPORTED: Duration = Duration::from_secs(5);

/// One watched picture's counts since its stretch began.
#[derive(Default)]
pub(crate) struct Pace {
    since: Option<Instant>,
    last: Option<Instant>,
    size: (u32, u32),
    came: u32,
    drawn: u32,
    replaced: u32,
    gaps: u32,
    longest: Duration,
}

impl Pace {
    /// A picture of `size` came at `now`; `replaced` when it took the place of
    /// one the window never drew. Answers a line to log when one is due.
    pub(crate) fn came(
        &mut self,
        now: Instant,
        size: (u32, u32),
        replaced: bool,
    ) -> Option<String> {
        let mut line = None;
        match self.last {
            Some(last) if now.saturating_duration_since(last) >= PAUSE => {
                line = self.finish(last);
                self.begin(now);
            }
            Some(last) => {
                let wait = now.saturating_duration_since(last);
                if wait >= GAP {
                    self.gaps += 1;
                }
                self.longest = self.longest.max(wait);
            }
            None => self.begin(now),
        }
        self.last = Some(now);
        self.size = size;
        self.came += 1;
        if replaced {
            self.replaced += 1;
        }
        if line.is_none()
            && self
                .since
                .is_some_and(|s| now.saturating_duration_since(s) >= REPORT_EVERY)
        {
            line = self.finish(now);
            self.begin(now);
        }
        line
    }

    /// The window took a picture to draw.
    pub(crate) fn drawn(&mut self) {
        self.drawn += 1;
    }

    /// The watch closed: its last stretch, when long enough to say anything.
    pub(crate) fn end(&self) -> Option<String> {
        self.finish(self.last?)
    }

    fn finish(&self, end: Instant) -> Option<String> {
        let span = end.saturating_duration_since(self.since?);
        if span < LEAST_REPORTED {
            return None;
        }
        let seconds = span.as_secs_f64();
        Some(format!(
            "watching: pictures in the last {:.0} s at {}x{}: {} came ({:.1} a second), {} drawn, {} replaced before they were drawn; {} waits over {} ms, the longest {} ms",
            seconds,
            self.size.0,
            self.size.1,
            self.came,
            f64::from(self.came) / seconds,
            self.drawn,
            self.replaced,
            self.gaps,
            GAP.as_millis(),
            self.longest.as_millis(),
        ))
    }

    /// A new stretch from `now`, knowing the last picture still.
    fn begin(&mut self, now: Instant) {
        *self = Pace {
            since: Some(now),
            last: self.last,
            ..Pace::default()
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SIZE: (u32, u32) = (1280, 720);

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }

    /// Pictures every `every` from `start` for `count`, each drawn; the lines.
    fn steady(pace: &mut Pace, start: Instant, every: Duration, count: u32) -> Vec<String> {
        (0..count)
            .filter_map(|i| {
                let line = pace.came(start + every * i, SIZE, false);
                pace.drawn();
                line
            })
            .collect()
    }

    #[test]
    fn a_steady_minute_reports_its_rate_and_no_gaps() {
        let start = Instant::now();
        let mut pace = Pace::default();
        let lines = steady(&mut pace, start, ms(16), 3800);
        assert_eq!(lines.len(), 1, "one minute, one line: {lines:?}");
        let line = &lines[0];
        assert!(line.contains("last 60 s at 1280x720"), "{line}");
        assert!(line.contains("62.5 a second"), "{line}");
        assert!(line.contains("0 replaced"), "{line}");
        assert!(
            line.contains("0 waits over 100 ms, the longest 16 ms"),
            "{line}"
        );
    }

    #[test]
    fn counts_the_waits_a_viewer_sees_and_the_longest() {
        let start = Instant::now();
        let mut pace = Pace::default();
        let mut at = start;
        for wait in [16, 16, 120, 16, 640, 16, 99] {
            at += ms(wait);
            pace.came(at, SIZE, false);
        }
        assert_eq!(pace.gaps, 2);
        assert_eq!(pace.longest, ms(640));
    }

    #[test]
    fn a_pause_ends_the_stretch_without_counting_as_a_gap() {
        let start = Instant::now();
        let mut pace = Pace::default();
        assert!(steady(&mut pace, start, ms(16), 600).is_empty());
        let back = start + ms(16 * 600) + Duration::from_secs(30);
        let line = pace
            .came(back, SIZE, false)
            .expect("the stretch before the pause");
        assert!(line.contains("0 waits over"), "{line}");
        assert!(line.contains("600 came"), "{line}");
        assert_eq!(
            (pace.came, pace.gaps),
            (1, 0),
            "a new stretch from the picture after"
        );
    }

    #[test]
    fn a_short_stretch_says_nothing() {
        let start = Instant::now();
        let mut pace = Pace::default();
        steady(&mut pace, start, ms(16), 100);
        assert_eq!(pace.end(), None);
        assert_eq!(Pace::default().end(), None, "nothing came");
    }

    #[test]
    fn the_end_reports_what_came_since_the_last_line() {
        let start = Instant::now();
        let mut pace = Pace::default();
        steady(&mut pace, start, ms(20), 500);
        pace.came(start + ms(20 * 500), SIZE, true);
        let line = pace.end().expect("ten seconds of pictures");
        assert!(line.contains("501 came"), "{line}");
        assert!(line.contains("500 drawn, 1 replaced"), "{line}");
    }
}
