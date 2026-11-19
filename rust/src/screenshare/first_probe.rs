//! When a share asks its connection to probe its path: once, as the
//! connection's first pictures flow.
//!
//! libwebrtc probes a new connection's path at once, and the probes go out
//! only with media. A share whose first pictures came late lost them: one
//! that started on a minimised window, or behind a slow capture start. It
//! then started from the 1 Mbps it is opened at, and since it sent all it was
//! allowed, which libwebrtc never probes, it climbed at about 8% a second. On
//! Windows 11 three of four shares took 20–30 s to reach a 17 Mbps cap, and a
//! window share that started minimised sat under 5 Mbps for 25 s (Nov 19
//! 2026). On Linux a share with no pictures for its first 10 s reached its
//! 12 Mbps cap 8–10 s after they began, against 2 s for one that moved from
//! the start. So the share asks for one probe, up to twice its cap, as its
//! pictures begin to flow (`Room::probe_publisher`, Rift's fork).
//!
//! Not on the first frame alone: a share nobody watches is paused by the
//! server and sends one picture in a while, and libwebrtc holds a probe to
//! twice what the tracks may send only while they send. On Windows 10 a probe
//! asked for then went to the connection's 100 Mbps ceiling (Nov 19 2026),
//! which a slow upload would have lost.

use std::time::Duration;

/// How often the share looks for its connection's first frames.
pub(crate) const LOOK_EVERY: Duration = Duration::from_secs(1);
/// The frames sent since the last look that say pictures flow: a paused
/// share sends one in a while, a moving one dozens.
const FLOWING: u32 = 10;
/// How often it looks once they went out, for a connection made again (a
/// full reconnect, a move to another room), whose count starts over.
pub(crate) const LOOK_AFTER: Duration = Duration::from_secs(5);

/// Whether the pictures flowing are a connection's first.
#[derive(Debug, Default)]
pub(crate) struct FirstFrames {
    /// The frames sent when last read.
    last: Option<u32>,
    /// Whether this connection's pictures were seen to flow.
    seen: bool,
}

impl FirstFrames {
    /// Notes the frames sent so far, and says whether to probe now: the first
    /// time pictures flow on this connection, while WebRTC's estimate
    /// (`available_bps`, 0 when it did not say) is under the cap.
    pub(crate) fn note(&mut self, frames_sent: u32, available_bps: f64, cap_bps: f64) -> bool {
        // WebRTC's count belongs to the connection, so a new one starts over.
        let before = match self.last {
            Some(last) if frames_sent >= last => last,
            Some(_) => {
                self.seen = false;
                0
            }
            None => 0,
        };
        self.last = Some(frames_sent);
        if self.seen || frames_sent - before < FLOWING {
            return false;
        }
        self.seen = true;
        available_bps < cap_bps
    }

    /// How long to wait before reading again.
    pub(crate) fn next_look(&self) -> Duration {
        if self.seen {
            LOOK_AFTER
        } else {
            LOOK_EVERY
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CAP: f64 = 12_000_000.0;

    #[test]
    fn the_first_pictures_to_flow_ask_for_one_probe() {
        let mut first = FirstFrames::default();
        assert!(!first.note(0, 1_000_000.0, CAP), "nothing sent yet");
        assert_eq!(first.next_look(), LOOK_EVERY);
        assert!(first.note(40, 1_000_000.0, CAP));
        assert!(!first.note(100, 1_200_000.0, CAP), "only once");
        assert_eq!(first.next_look(), LOOK_AFTER);
    }

    #[test]
    fn an_estimate_already_at_the_cap_needs_none() {
        let mut first = FirstFrames::default();
        assert!(!first.note(60, 26_000_000.0, CAP));
        assert!(
            !first.note(120, 1_000_000.0, CAP),
            "and it was the first frames"
        );
    }

    #[test]
    fn a_paused_share_waits_for_its_pictures_to_flow() {
        // Nobody watches: the server paused it, and one picture went out.
        let mut first = FirstFrames::default();
        assert!(!first.note(1, 1_000_000.0, CAP));
        assert!(!first.note(2, 1_000_000.0, CAP));
        assert_eq!(first.next_look(), LOOK_EVERY);
        // Someone watches.
        assert!(first.note(50, 1_000_000.0, CAP));
    }

    #[test]
    fn an_estimate_not_given_still_probes() {
        assert!(FirstFrames::default().note(60, 0.0, CAP));
    }

    #[test]
    fn a_new_connection_probes_again() {
        let mut first = FirstFrames::default();
        assert!(first.note(600, 2_000_000.0, CAP));
        assert!(!first.note(900, 2_000_000.0, CAP));
        assert!(
            !first.note(0, 0.0, CAP),
            "made again, nothing sent on it yet"
        );
        assert_eq!(first.next_look(), LOOK_EVERY);
        assert!(first.note(30, 1_000_000.0, CAP));
    }
}
