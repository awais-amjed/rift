//! Holding a GPU share to the rate WebRTC asks for, by leaving pictures out
//! before they are encoded.
//!
//! WebRTC drops nothing of a GPU share. Its frame dropper is off for
//! pre-encoded frames (`webrtc-sys` 0.3.49), because a dropped H264
//! frame breaks every frame after it until the next keyframe. So whatever an
//! encoder makes beyond WebRTC's target waits in WebRTC's send queue, and on
//! a link that cannot carry it the picture falls further behind its sound
//! the longer it runs. Encoders do overshoot: one in variable bitrate on a
//! fast game, or one slow to follow a target that has just fallen. A picture
//! left out before the encoder breaks nothing; the viewer sees a lower frame
//! rate instead of a late picture.

use std::time::Instant;

/// How far the encoder may run ahead of the target before pictures are left
/// out, in seconds at the target rate: the most the picture can fall behind
/// on the way out, beyond WebRTC's own pacing. A keyframe takes a few
/// pictures' worth in one go, so less than this closes the gate after every
/// keyframe a viewer asks for.
const AHEAD_SECONDS: f64 = 0.2;

/// How often the pictures left out are reported in the log.
const REPORT_SECONDS: f64 = 5.0;

/// How long after a keyframe a picture left out is counted as the
/// keyframe's doing. A keyframe is asked for whenever a viewer joins or loses
/// packets, and costs many pictures' worth at once, so what it leaves out is
/// left out for every viewer.
const AFTER_KEYFRAME_SECONDS: f64 = 1.0;

/// What the gate saw since its last report.
#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct GateReport {
    pub left_out: u32,
    /// Of those, the ones within [`AFTER_KEYFRAME_SECONDS`] of a keyframe.
    pub left_out_after_keyframes: u32,
    pub keyframes: u32,
    pub keyframe_bytes: u64,
}

/// A leaky bucket of encoded bits, emptied at WebRTC's target.
#[derive(Debug)]
pub(crate) struct RateGate {
    /// Bits made and not yet covered by the target.
    ahead_bits: f64,
    target_bps: u32,
    at: Option<Instant>,
    last_keyframe: Option<Instant>,
    counts: GateReport,
    reported_at: Option<Instant>,
}

impl RateGate {
    pub(crate) fn new() -> RateGate {
        RateGate {
            ahead_bits: 0.0,
            target_bps: 0,
            at: None,
            last_keyframe: None,
            counts: GateReport::default(),
            reported_at: None,
        }
    }

    /// Count a frame the encoder made.
    pub(crate) fn spent(&mut self, bytes: usize, keyframe: bool, now: Instant) {
        self.drain(now);
        self.ahead_bits += bytes as f64 * 8.0;
        if keyframe {
            self.last_keyframe = Some(now);
            self.counts.keyframes += 1;
            self.counts.keyframe_bytes += bytes as u64;
        }
    }

    /// Whether the next picture goes to the encoder, at what WebRTC now asks
    /// for. One that does not is counted, for the log.
    pub(crate) fn admits(&mut self, target_bps: u32, now: Instant) -> bool {
        self.drain(now);
        self.target_bps = target_bps;
        let open = self.ahead_bits <= f64::from(target_bps) * AHEAD_SECONDS;
        if !open {
            self.counts.left_out += 1;
            if self
                .last_keyframe
                .is_some_and(|key| now.duration_since(key).as_secs_f64() <= AFTER_KEYFRAME_SECONDS)
            {
                self.counts.left_out_after_keyframes += 1;
            }
        }
        open
    }

    /// The pictures left out and the keyframes made since the last report,
    /// once every [`REPORT_SECONDS`] while there are any.
    pub(crate) fn report(&mut self, now: Instant) -> Option<GateReport> {
        let since = *self.reported_at.get_or_insert(now);
        let quiet = self.counts.left_out == 0 && self.counts.keyframes == 0;
        if quiet || now.duration_since(since).as_secs_f64() < REPORT_SECONDS {
            return None;
        }
        self.reported_at = Some(now);
        Some(std::mem::take(&mut self.counts))
    }

    fn drain(&mut self, now: Instant) {
        if let Some(at) = self.at {
            let sent = f64::from(self.target_bps) * now.duration_since(at).as_secs_f64();
            self.ahead_bits = (self.ahead_bits - sent).max(0.0);
        }
        self.at = Some(now);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    const TARGET: u32 = 6_000_000;
    const FPS: u32 = 60;

    /// Run `seconds` of pictures at [`FPS`], each encoded to `bytes(n)` when
    /// the gate admits it, and say how many it admitted.
    fn run(gate: &mut RateGate, start: Instant, seconds: u32, bytes: impl Fn(u32) -> usize) -> u32 {
        let mut admitted = 0;
        for n in 0..seconds * FPS {
            let now = start + Duration::from_secs_f64(f64::from(n) / f64::from(FPS));
            if gate.admits(TARGET, now) {
                admitted += 1;
                gate.spent(bytes(n), n == 0, now);
            }
        }
        admitted
    }

    fn frame_at(bps: u32) -> usize {
        (bps / FPS / 8) as usize
    }

    #[test]
    fn an_encoder_at_the_target_loses_nothing() {
        let mut gate = RateGate::new();
        assert_eq!(
            run(&mut gate, Instant::now(), 10, |_| frame_at(TARGET)),
            10 * FPS
        );
    }

    #[test]
    fn an_encoder_at_twice_the_target_gets_half_the_pictures_through() {
        let mut gate = RateGate::new();
        let admitted = run(&mut gate, Instant::now(), 10, |_| frame_at(2 * TARGET));
        let half = 10 * FPS / 2;
        assert!(
            admitted.abs_diff(half) <= FPS / 4,
            "{admitted} of {}",
            10 * FPS
        );
    }

    #[test]
    fn a_keyframe_leaves_out_only_the_pictures_it_ran_over_by() {
        let mut gate = RateGate::new();
        // A keyframe of 30 pictures' worth, the rest at the target: the gate
        // holds about the excess beyond what it allows ahead, then reopens.
        let admitted = run(&mut gate, Instant::now(), 2, |n| {
            frame_at(TARGET) * if n == 0 { 30 } else { 1 }
        });
        let allowed = (AHEAD_SECONDS * f64::from(FPS)) as u32;
        let left_out = 2 * FPS - admitted;
        assert!(left_out.abs_diff(29 - allowed) <= 1, "{left_out} left out");
    }

    #[test]
    fn a_falling_target_closes_the_gate_at_once() {
        let mut gate = RateGate::new();
        let start = Instant::now();
        // At the target for a second, then the target drops to a third while
        // the encoder takes a moment to follow.
        assert_eq!(run(&mut gate, start, 1, |_| frame_at(TARGET)), FPS);
        let later = start + Duration::from_secs(1);
        let mut admitted = 0u32;
        for n in 0..FPS {
            let now = later + Duration::from_secs_f64(f64::from(n) / f64::from(FPS));
            if gate.admits(TARGET / 3, now) {
                admitted += 1;
                gate.spent(frame_at(TARGET), false, now);
            }
        }
        assert!(admitted.abs_diff(FPS / 3) <= FPS / 10, "{admitted}");
    }

    #[test]
    fn reports_what_it_left_out_now_and_then() {
        let mut gate = RateGate::new();
        let start = Instant::now();
        assert_eq!(gate.report(start), None);
        run(&mut gate, start, 6, |_| frame_at(2 * TARGET));
        let report = gate
            .report(start + Duration::from_secs(6))
            .expect("a report");
        assert!(report.left_out > 0);
        assert_eq!(gate.report(start + Duration::from_secs(7)), None);
    }

    #[test]
    fn what_a_keyframe_leaves_out_is_counted_apart() {
        let mut gate = RateGate::new();
        let start = Instant::now();
        assert_eq!(gate.report(start), None);
        // A keyframe of 30 pictures' worth, the rest at the target.
        run(&mut gate, start, 6, |n| {
            frame_at(TARGET) * if n == 0 { 30 } else { 1 }
        });
        let report = gate
            .report(start + Duration::from_secs(6))
            .expect("a report");
        assert_eq!(report.keyframes, 1);
        assert_eq!(report.keyframe_bytes, 30 * frame_at(TARGET) as u64);
        assert!(report.left_out > 0);
        assert_eq!(report.left_out_after_keyframes, report.left_out);
    }

    #[test]
    fn an_overshoot_away_from_keyframes_is_not_theirs() {
        let mut gate = RateGate::new();
        let start = Instant::now();
        assert_eq!(gate.report(start), None);
        // The first picture is a keyframe at the target; then the encoder
        // runs at twice the target for good.
        run(&mut gate, start, 6, |_| frame_at(2 * TARGET));
        let report = gate
            .report(start + Duration::from_secs(6))
            .expect("a report");
        assert_eq!(report.keyframes, 1);
        // Half of every second's pictures are left out; only the first
        // second's count as the keyframe's.
        assert!(report.left_out_after_keyframes <= FPS / 2 + 1, "{report:?}");
        let rest = report.left_out - report.left_out_after_keyframes;
        assert!(rest.abs_diff(5 * FPS / 2) <= FPS / 4, "{report:?}");
    }

    #[test]
    fn keyframes_alone_are_reported() {
        let mut gate = RateGate::new();
        let start = Instant::now();
        assert_eq!(gate.report(start), None);
        gate.spent(1000, true, start);
        let report = gate
            .report(start + Duration::from_secs(6))
            .expect("a report");
        assert_eq!(report.keyframes, 1);
        assert_eq!(report.left_out, 0);
    }
}
