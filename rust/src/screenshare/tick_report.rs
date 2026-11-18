//! How libwebrtc's capturer keeps up, for the log.
//!
//! A whole screen on Windows 10 (and any share Rift's own capture does not
//! take) is captured by libwebrtc on the share's capture thread, one call a
//! tick: on Windows a DXGI duplication, a copy to memory and a wait for the
//! GPU. Beside a game that fills the GPU a tick can outlast its interval, and
//! the share then quietly runs below its rate ("Behind" in `capture::run`).
//! A friend's whole-screen RDR2 share went to 1–18 fps and the log could not
//! say whether capture was the reason (Nov 18 2026), so the ticks are timed
//! and said every few seconds. People send the log with a bug report, and
//! none of this is secret.

use std::time::{Duration, Instant};

/// How often the ticks are reported.
const REPORT_SECONDS: f64 = 5.0;

/// The ticks since the last report.
#[derive(Debug, Default)]
pub(crate) struct CaptureTicks {
    ticks: u32,
    busy: Duration,
    longest: Duration,
    /// Ticks that ended past the next one's time.
    behind: u32,
    reported_at: Option<Instant>,
}

/// What the ticks since the last report took.
#[derive(Debug, PartialEq)]
pub(crate) struct TicksReport {
    pub ticks: u32,
    pub seconds: f64,
    pub average_ms: f64,
    pub longest_ms: f64,
    pub behind: u32,
}

impl CaptureTicks {
    /// Count one tick that took `took`, and whether it ran past the next.
    pub(crate) fn add(&mut self, took: Duration, behind: bool) {
        self.ticks += 1;
        self.busy += took;
        self.longest = self.longest.max(took);
        self.behind += u32::from(behind);
    }

    /// The ticks since the last report, once every [`REPORT_SECONDS`].
    pub(crate) fn report(&mut self, now: Instant) -> Option<TicksReport> {
        let since = *self.reported_at.get_or_insert(now);
        let seconds = now.duration_since(since).as_secs_f64();
        if self.ticks == 0 || seconds < REPORT_SECONDS {
            return None;
        }
        let report = TicksReport {
            ticks: self.ticks,
            seconds,
            average_ms: self.busy.as_secs_f64() * 1000.0 / f64::from(self.ticks),
            longest_ms: self.longest.as_secs_f64() * 1000.0,
            behind: self.behind,
        };
        *self = CaptureTicks {
            reported_at: Some(now),
            ..CaptureTicks::default()
        };
        Some(report)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }

    #[test]
    fn nothing_is_said_before_the_time_is_up() {
        let start = Instant::now();
        let mut ticks = CaptureTicks::default();
        assert_eq!(ticks.report(start), None);
        ticks.add(ms(4), false);
        assert_eq!(ticks.report(start + ms(4_999)), None);
    }

    #[test]
    fn a_report_averages_the_ticks_and_starts_again() {
        let start = Instant::now();
        let mut ticks = CaptureTicks::default();
        ticks.report(start);
        ticks.add(ms(4), false);
        ticks.add(ms(20), true);
        ticks.add(ms(6), false);
        let report = ticks.report(start + ms(5_000)).expect("a report");
        assert_eq!(report.ticks, 3);
        assert!((report.average_ms - 10.0).abs() < 1e-9);
        assert!((report.longest_ms - 20.0).abs() < 1e-9);
        assert_eq!(report.behind, 1);
        assert!((report.seconds - 5.0).abs() < 1e-9);
        // The next report counts from this one.
        ticks.add(ms(1), false);
        assert_eq!(ticks.report(start + ms(9_000)), None);
        assert_eq!(ticks.report(start + ms(10_000)).map(|r| r.ticks), Some(1));
    }

    #[test]
    fn no_ticks_no_report() {
        let start = Instant::now();
        let mut ticks = CaptureTicks::default();
        ticks.report(start);
        assert_eq!(ticks.report(start + ms(60_000)), None);
    }
}
