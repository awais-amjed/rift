//! Holding a GPU share to the rate WebRTC asks for, by leaving pictures out
//! before they are encoded.
//!
//! WebRTC drops nothing of a GPU share. Its frame dropper is off for
//! pre-encoded frames (`third_party/webrtc-sys`), because a dropped H264
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

/// A leaky bucket of encoded bits, emptied at WebRTC's target.
#[derive(Debug)]
pub(crate) struct RateGate {
    /// Bits made and not yet covered by the target.
    ahead_bits: f64,
    target_bps: u32,
    at: Option<Instant>,
    left_out: u32,
    reported_at: Option<Instant>,
}

impl RateGate {
    pub(crate) fn new() -> RateGate {
        RateGate {
            ahead_bits: 0.0,
            target_bps: 0,
            at: None,
            left_out: 0,
            reported_at: None,
        }
    }

    /// Count a frame the encoder made.
    pub(crate) fn spent(&mut self, bytes: usize, now: Instant) {
        self.drain(now);
        self.ahead_bits += bytes as f64 * 8.0;
    }

    /// Whether the next picture goes to the encoder, at what WebRTC now asks
    /// for. One that does not is counted, for the log.
    pub(crate) fn admits(&mut self, target_bps: u32, now: Instant) -> bool {
        self.drain(now);
        self.target_bps = target_bps;
        let open = self.ahead_bits <= f64::from(target_bps) * AHEAD_SECONDS;
        if !open {
            self.left_out += 1;
        }
        open
    }

    /// The pictures left out since the last report, once every
    /// [`REPORT_SECONDS`] while there are any.
    pub(crate) fn report(&mut self, now: Instant) -> Option<u32> {
        let since = *self.reported_at.get_or_insert(now);
        if self.left_out == 0 || now.duration_since(since).as_secs_f64() < REPORT_SECONDS {
            return None;
        }
        self.reported_at = Some(now);
        Some(std::mem::take(&mut self.left_out))
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
                gate.spent(bytes(n), now);
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
                gate.spent(frame_at(TARGET), now);
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
        let left_out = gate
            .report(start + Duration::from_secs(6))
            .expect("a report");
        assert!(left_out > 0);
        assert_eq!(gate.report(start + Duration::from_secs(7)), None);
    }
}
