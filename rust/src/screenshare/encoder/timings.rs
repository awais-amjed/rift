//! Where an encoder's time goes, picture by picture, for the log.
//!
//! On Windows FFmpeg's NVENC made 59.9 fps at 60 but only 88.5 at 120 on an
//! RTX 3070 Ti Laptop, 11.7 ms a picture in the share against 4.1 in a C
//! harness on the same library, and nothing said where the rest went (Oct 9
//! 2026). So the session times handing the picture in, waiting for the
//! encoder, and handing the result to LiveKit, and says so every few seconds.
//! People send the log with a bug report, and none of this is secret.

use std::time::{Duration, Instant};

/// How often the times are reported.
const REPORT_SECONDS: f64 = 5.0;

/// The times since the last report.
#[derive(Debug, Default)]
pub(super) struct EncodeTimes {
    pictures: u32,
    send: Duration,
    encode: Duration,
    deliver: Duration,
    longest: Duration,
    reported_at: Option<Instant>,
}

/// Each part's average over the pictures reported, and the longest picture.
#[derive(Debug, PartialEq)]
pub(super) struct TimesReport {
    pub pictures: u32,
    pub send_ms: f64,
    pub encode_ms: f64,
    pub deliver_ms: f64,
    pub longest_ms: f64,
}

impl EncodeTimes {
    /// Count one picture: handing it to the encoder, waiting for what it
    /// made, and delivering that.
    pub(super) fn add(&mut self, send: Duration, encode: Duration, deliver: Duration) {
        self.pictures += 1;
        self.send += send;
        self.encode += encode;
        self.deliver += deliver;
        self.longest = self.longest.max(send + encode + deliver);
    }

    /// The times since the last report, once every [`REPORT_SECONDS`] while
    /// pictures are coming.
    pub(super) fn report(&mut self, now: Instant) -> Option<TimesReport> {
        let since = *self.reported_at.get_or_insert(now);
        if self.pictures == 0 || now.duration_since(since).as_secs_f64() < REPORT_SECONDS {
            return None;
        }
        let ms = |total: Duration| total.as_secs_f64() * 1000.0 / f64::from(self.pictures);
        let report = TimesReport {
            pictures: self.pictures,
            send_ms: ms(self.send),
            encode_ms: ms(self.encode),
            deliver_ms: ms(self.deliver),
            longest_ms: self.longest.as_secs_f64() * 1000.0,
        };
        *self = EncodeTimes {
            reported_at: Some(now),
            ..EncodeTimes::default()
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
    fn reports_each_parts_average_and_the_longest_picture() {
        let mut times = EncodeTimes::default();
        let start = Instant::now();
        assert_eq!(times.report(start), None);
        times.add(ms(1), ms(8), ms(1));
        times.add(ms(3), ms(12), ms(1));
        let report = times.report(start + ms(5000)).expect("a report");
        assert_eq!(report.pictures, 2);
        assert!((report.send_ms - 2.0).abs() < 1e-9);
        assert!((report.encode_ms - 10.0).abs() < 1e-9);
        assert!((report.deliver_ms - 1.0).abs() < 1e-9);
        assert!((report.longest_ms - 16.0).abs() < 1e-9);
    }

    #[test]
    fn waits_between_reports_and_starts_over_after_one() {
        let mut times = EncodeTimes::default();
        let start = Instant::now();
        assert_eq!(times.report(start), None);
        times.add(ms(1), ms(1), ms(1));
        assert_eq!(times.report(start + ms(1000)), None);
        assert!(times.report(start + ms(5000)).is_some());
        // Nothing since: nothing to say.
        assert_eq!(times.report(start + ms(11000)), None);
        times.add(ms(2), ms(2), ms(2));
        let report = times.report(start + ms(11000)).expect("a report");
        assert_eq!(report.pictures, 1);
        assert!((report.longest_ms - 6.0).abs() < 1e-9);
    }
}
