//! When a picture that has stopped changing is sent again.
//!
//! A capture that only hands over what changed sends nothing on a still
//! screen, and WebRTC needs a picture to answer a viewer's keyframe request
//! with: a Wayland compositor's stream (`capture_pw.rs`), and Windows 10's
//! screen capturer once Rift leaves out the pictures it marks unchanged
//! (`capture.rs`). Both send the last picture again on this clock.

use std::time::{Duration, Instant};

/// How long a still picture waits before it is sent again. LiveKit's own
/// keepalive runs at this rate too.
pub(super) const REPEAT_EVERY: Duration = Duration::from_millis(100);

/// The repeat once a picture has been still for [`SETTLED_AFTER`]: by then
/// the quick repeats have sharpened it, and each one is an encode. The same
/// back-off libwebrtc's own still-screen mode makes (its zero-hertz idle
/// repeat), owner's call Oct 30.
pub(super) const REPEAT_IDLE: Duration = Duration::from_secs(1);

/// How long after a new picture the repeats stay at [`REPEAT_EVERY`].
pub(super) const SETTLED_AFTER: Duration = Duration::from_secs(2);

/// When the last picture was sent, and when a new one last came.
#[derive(Debug, Clone, Copy)]
pub(super) struct Repeats {
    /// When the last picture was sent, new or again.
    since: Instant,
    /// When a new one came.
    fresh: Instant,
}

impl Repeats {
    pub(super) fn new(now: Instant) -> Self {
        Self {
            since: now,
            fresh: now,
        }
    }

    /// A new picture was sent.
    pub(super) fn fresh(&mut self, now: Instant) {
        self.since = now;
        self.fresh = now;
    }

    /// The last picture was sent again.
    pub(super) fn repeated(&mut self, now: Instant) {
        self.since = now;
    }

    /// Whether the last picture is due to be sent again.
    pub(super) fn due(&self, now: Instant) -> bool {
        let wait = if now.saturating_duration_since(self.fresh) < SETTLED_AFTER {
            REPEAT_EVERY
        } else {
            REPEAT_IDLE
        };
        now.saturating_duration_since(self.since) >= wait
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_new_picture_is_repeated_quickly_then_once_a_second() {
        let start = Instant::now();
        let mut repeats = Repeats::new(start);
        assert!(!repeats.due(start + Duration::from_millis(99)));
        assert!(repeats.due(start + REPEAT_EVERY));
        let settled = start + SETTLED_AFTER;
        repeats.repeated(settled);
        assert!(!repeats.due(settled + REPEAT_EVERY));
        assert!(repeats.due(settled + REPEAT_IDLE));
        // A new picture goes back to the quick repeats.
        let new = settled + REPEAT_IDLE;
        repeats.fresh(new);
        assert!(repeats.due(new + REPEAT_EVERY));
    }
}
