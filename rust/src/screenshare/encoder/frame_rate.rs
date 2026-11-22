//! The encoder's rate, for the pictures that actually come.
//!
//! A GPU encoder is opened at the share's frame rate and counts its budget in
//! pictures: asked for 11 Mbps at 60 fps it gives each picture about 183
//! kbit. When fewer come, a game's window drawing at 40, capture falling
//! behind beside a game, it sends that much less, and WebRTC, seeing the
//! share send well under its target, lowers its estimate to what is sent.
//! The next picture's budget shrinks with it, and the share talks itself
//! down to a few small pictures a second (the Nov 18 2026 review, A1: a
//! friend's whole-screen RDR2 share at 0.3 to 2 Mbps on a 100 Mbps line).
//!
//! So the rate handed to the encoder is WebRTC's target scaled by how many
//! pictures it is opened for against how many reached the share's feed,
//! which is what WebRTC's target then means per picture. They are counted
//! before the rate gate: counted after, every picture the gate leaves out
//! would make the next ones bigger, and the gate leave out more.

use std::time::{Duration, Instant};

/// How long the pictures are counted over before the rate is set again.
const WINDOW: Duration = Duration::from_secs(1);

/// The most the rate is scaled by: past it, a picture after a still spell
/// would be one budgeted for a third of a second or more, and the rate gate
/// leaves the next ones out.
const MOST: f64 = 3.0;

/// How far the scale must rise before it is raised, so a rate wavering
/// round its mark does not move the encoder every second.
const STEP: f64 = 0.1;

/// How far the scale may sit above what the pictures coming call for before
/// it is lowered. Above it, each picture is budgeted for more than its share,
/// and the rate gate leaves out the difference: held to the step, a scale
/// raised to 1.10 by one slow second stayed there while 59 of 60 came, and an
/// RX 9070 XT's Warzone share had up to 40 of every 300 pictures left out
/// (Nov 22 2026). Lowered at once, the encoder at worst sends a little under
/// WebRTC's target, which it then gives back.
const SLACK: f64 = 0.02;

/// The scale from the frame rate the encoder was opened at to the one coming.
#[derive(Debug)]
pub(super) struct FrameRateScale {
    nominal_fps: u32,
    /// Pictures offered when the window began, and when it began.
    since: Option<(u32, Instant)>,
    scale: f64,
    /// What the last window called for, when that was a step above the
    /// scale: one slow second alone does not raise it, a second in a row does.
    rising: Option<f64>,
}

impl FrameRateScale {
    pub(super) fn new(nominal_fps: u32) -> FrameRateScale {
        FrameRateScale {
            nominal_fps: nominal_fps.max(1),
            since: None,
            scale: 1.0,
            rising: None,
        }
    }

    /// Take the running count of pictures offered to the share's feed. Once
    /// a window has passed, the scale follows the rate they came at.
    pub(super) fn observe(&mut self, offered: u32, now: Instant) {
        let Some((at_start, start)) = self.since else {
            self.since = Some((offered, now));
            return;
        };
        let elapsed = now.duration_since(start);
        if elapsed < WINDOW {
            return;
        }
        let came = offered.wrapping_sub(at_start);
        self.since = Some((offered, now));
        let fps = f64::from(came) / elapsed.as_secs_f64();
        // Nothing came: a still screen sends nothing to encode, and the
        // first picture after it needs no budget a game's would not.
        if came == 0 {
            return;
        }
        let scale = (f64::from(self.nominal_fps) / fps).clamp(1.0, MOST);
        if scale >= self.scale + STEP {
            // Raised once two windows in a row call for it, to the lesser.
            if let Some(before) = self.rising.replace(scale) {
                self.scale = before.min(scale);
                self.rising = None;
            }
            return;
        }
        self.rising = None;
        if scale < self.scale - SLACK || (scale == 1.0 && self.scale != 1.0) {
            self.scale = scale;
        }
    }

    /// The rate to give the encoder for WebRTC's `target_bps`.
    pub(super) fn rate(&self, target_bps: u32) -> u32 {
        (f64::from(target_bps) * self.scale)
            .round()
            .min(f64::from(u32::MAX)) as u32
    }

    pub(super) fn scale(&self) -> f64 {
        self.scale
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(n: u64) -> Duration {
        Duration::from_millis(n)
    }

    /// Feed `fps` pictures a second for `seconds`, observing every 100 ms.
    fn feed(
        scale: &mut FrameRateScale,
        start: Instant,
        offered: &mut u32,
        from_s: u64,
        seconds: u64,
        fps: u32,
    ) {
        let base = *offered;
        for n in 1..=seconds * 10 {
            // Exactly `fps` a second, spread over the ticks.
            *offered = base + (u64::from(fps) * n / 10) as u32;
            scale.observe(*offered, start + ms(from_s * 1000 + n * 100));
        }
    }

    #[test]
    fn a_full_rate_leaves_the_target_alone() {
        let start = Instant::now();
        let mut scale = FrameRateScale::new(60);
        let mut offered = 0;
        scale.observe(0, start);
        feed(&mut scale, start, &mut offered, 0, 5, 60);
        assert_eq!(scale.rate(11_000_000), 11_000_000);
    }

    #[test]
    fn fewer_pictures_get_more_each() {
        let start = Instant::now();
        let mut scale = FrameRateScale::new(60);
        let mut offered = 0;
        scale.observe(0, start);
        feed(&mut scale, start, &mut offered, 0, 3, 30);
        assert_eq!(scale.rate(10_000_000), 20_000_000);
    }

    #[test]
    fn the_scale_stops_at_its_most() {
        let start = Instant::now();
        let mut scale = FrameRateScale::new(60);
        let mut offered = 0;
        scale.observe(0, start);
        feed(&mut scale, start, &mut offered, 0, 3, 10);
        assert_eq!(scale.rate(1_000_000), 3_000_000);
    }

    #[test]
    fn a_still_screen_keeps_the_last_scale() {
        let start = Instant::now();
        let mut scale = FrameRateScale::new(60);
        let mut offered = 0;
        scale.observe(0, start);
        feed(&mut scale, start, &mut offered, 0, 2, 30);
        assert!((scale.scale() - 2.0).abs() < 1e-9);
        feed(&mut scale, start, &mut offered, 2, 3, 0);
        assert!((scale.scale() - 2.0).abs() < 1e-9);
    }

    #[test]
    fn small_rises_do_not_change_it_but_any_fall_past_the_slack_does() {
        let start = Instant::now();
        let mut scale = FrameRateScale::new(60);
        let mut offered = 0;
        scale.observe(0, start);
        feed(&mut scale, start, &mut offered, 0, 3, 40);
        assert!((scale.scale() - 1.5).abs() < 1e-9);
        // 1.5 to about 1.43: lowered, or each picture would get more than
        // its share.
        feed(&mut scale, start, &mut offered, 3, 2, 42);
        assert!((scale.scale() - 60.0 / 42.0).abs() < 1e-9);
        // Up to 1.5 again: under the step, kept.
        feed(&mut scale, start, &mut offered, 5, 3, 40);
        assert!((scale.scale() - 60.0 / 42.0).abs() < 1e-9);
        // Back to the full rate, by any amount.
        feed(&mut scale, start, &mut offered, 8, 2, 60);
        assert!((scale.scale() - 1.0).abs() < 1e-9);
    }

    #[test]
    fn one_slow_second_does_not_raise_it_nor_does_the_scale_stick_above_the_rate() {
        let start = Instant::now();
        let mut scale = FrameRateScale::new(60);
        let mut offered = 0;
        scale.observe(0, start);
        // One second at 50, then 59 a second: never raised (Warzone, Nov 22).
        feed(&mut scale, start, &mut offered, 0, 1, 50);
        feed(&mut scale, start, &mut offered, 1, 5, 59);
        assert!((scale.scale() - 1.0).abs() < 1e-9);
        // Raised for two slow seconds, then lowered as soon as 59 come again,
        // not held a step above them.
        feed(&mut scale, start, &mut offered, 6, 2, 50);
        assert!((scale.scale() - 1.2).abs() < 1e-9);
        feed(&mut scale, start, &mut offered, 8, 2, 59);
        assert!(scale.scale() < 1.0 + SLACK, "{}", scale.scale());
    }

    #[test]
    fn nothing_moves_before_a_window_has_passed() {
        let start = Instant::now();
        let mut scale = FrameRateScale::new(60);
        scale.observe(0, start);
        scale.observe(5, start + ms(900));
        assert!((scale.scale() - 1.0).abs() < 1e-9);
    }
}
