//! When a keyframe asked for again goes out.
//!
//! When too much sent goes unacknowledged, WebRTC's congestion window drops every
//! Nth frame before the pass-through encoder sees it. That encoder then holds the
//! deltas that follow, since they no longer decode, and asks for a keyframe. So at
//! a low rate frames ran key, delta, key, delta, and with every second frame dropped
//! each keyframe was. Nothing went out, so nothing was acknowledged and the window
//! never reopened: the share stopped for good, in 4 of 8 H265 shares on a 1 Mbps
//! upload (Nov 8 2026, `CALLS.md`, "A share that stopped on a slow upload").
//!
//! Each keyframe asked for again as soon as it could be waits one picture longer
//! than the last, so no fixed N keeps landing on it. The first goes at once, as a
//! viewer joining just after a share starts wants, and two together are harmless:
//! the lock needs a delta between them.
//!
//! A keyframe a viewer asks for, having joined or lost packets, goes to every
//! viewer, since a share is one stream, and the rate gate then leaves pictures
//! out to pay for it. A viewer whose link loses packets all the time asked
//! twice a second, as often as LiveKit lets a request through, so everyone's
//! picture stuttered for one viewer (a review of a game share, Nov 18 2026).
//! So a viewer's request waits until [`VIEWER_KEY_EVERY`] after the last
//! keyframe. One to mend the chain the pass-through encoder holds, which every
//! viewer is waiting for, never does ([`Keyframes`]).
use std::time::{Duration, Instant};

use super::KeyframeWanted;

/// The least time from one keyframe to the next that a viewer asked for.
pub(super) const VIEWER_KEY_EVERY: Duration = Duration::from_secs(1);

/// The most pictures a keyframe asked for waits. Long enough not to be reached
/// before a keyframe gets through.
const MOST_DELTAS_BETWEEN: u32 = 8;

#[derive(Debug)]
pub(super) struct KeyframePacing {
    deltas_since_key: u32,
    deltas_between: u32,
}

impl KeyframePacing {
    pub(super) fn new() -> KeyframePacing {
        KeyframePacing {
            deltas_since_key: u32::MAX,
            deltas_between: 0,
        }
    }

    /// Whether a keyframe asked for may be the next picture.
    pub(super) fn allows_key(&self) -> bool {
        self.deltas_since_key >= self.deltas_between
    }

    /// A picture was encoded.
    pub(super) fn encoded(&mut self, keyframe: bool) {
        if !keyframe {
            self.deltas_since_key = self.deltas_since_key.saturating_add(1);
            return;
        }
        self.deltas_between = if self.deltas_since_key <= self.deltas_between + 1 {
            (self.deltas_between + 1).min(MOST_DELTAS_BETWEEN)
        } else {
            0
        };
        self.deltas_since_key = 0;
    }
}

/// The keyframes wanted, and when the next may go.
#[derive(Debug)]
pub(super) struct Keyframes {
    pacing: KeyframePacing,
    /// Every viewer waits for it: the share's first picture, or the chain
    /// broken.
    mend: bool,
    /// A viewer asked.
    viewer: bool,
    last: Option<Instant>,
}

impl Keyframes {
    /// The first picture is a keyframe.
    pub(super) fn new() -> Keyframes {
        Keyframes {
            pacing: KeyframePacing::new(),
            mend: true,
            viewer: false,
            last: None,
        }
    }

    pub(super) fn heard(&mut self, wanted: KeyframeWanted) {
        match wanted {
            KeyframeWanted::No => {}
            KeyframeWanted::Viewer => self.viewer = true,
            KeyframeWanted::Mend => self.mend = true,
        }
    }

    /// Whether a keyframe is wanted by `now`.
    pub(super) fn due(&self, now: Instant) -> bool {
        self.mend
            || (self.viewer
                && self
                    .last
                    .is_none_or(|at| now.saturating_duration_since(at) >= VIEWER_KEY_EVERY))
    }

    /// Whether the next picture is to be a keyframe.
    pub(super) fn next(&self, now: Instant) -> bool {
        self.due(now) && self.pacing.allows_key()
    }

    /// A picture was encoded at `now`.
    pub(super) fn encoded(&mut self, keyframe: bool, now: Instant) {
        self.pacing.encoded(keyframe);
        if keyframe {
            self.mend = false;
            self.viewer = false;
            self.last = Some(now);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A share whose chain is broken, under WebRTC's congestion window dropping every
    /// `nth` frame from `phase` on: how many pictures until a keyframe gets through.
    fn pictures_until_a_key_gets_through(
        nth: u32,
        phase: u32,
        allows: impl Fn(&KeyframePacing) -> bool,
    ) -> Option<u32> {
        let mut pacing = KeyframePacing::new();
        let mut asked = true;
        for picture in 0..200u32 {
            let keyframe = asked && allows(&pacing);
            pacing.encoded(keyframe);
            if keyframe {
                asked = false;
            }
            let dropped = (picture + phase) % nth == 0;
            if dropped {
                continue;
            }
            if keyframe {
                return Some(picture);
            }
            // The pass-through encoder holds a delta after a gap and asks again.
            asked = true;
        }
        None
    }

    #[test]
    fn asking_at_once_never_gets_through_every_second_frame_dropped() {
        // What stopped the share: the behaviour this replaces.
        assert_eq!(pictures_until_a_key_gets_through(2, 0, |_| true), None);
    }

    #[test]
    fn a_keyframe_gets_through_any_regular_drop() {
        for nth in 2..=12 {
            for phase in 0..nth {
                let through =
                    pictures_until_a_key_gets_through(nth, phase, KeyframePacing::allows_key);
                assert!(
                    through.is_some_and(|picture| picture <= 7),
                    "every {nth}th frame dropped, phase {phase}: {through:?}"
                );
            }
        }
    }

    #[test]
    fn the_first_keyframe_goes_at_once() {
        assert!(KeyframePacing::new().allows_key());
    }

    #[test]
    fn a_keyframe_asked_for_long_after_the_last_goes_at_once() {
        let mut pacing = KeyframePacing::new();
        pacing.encoded(true);
        for _ in 0..60 {
            pacing.encoded(false);
        }
        assert!(pacing.allows_key());
    }

    #[test]
    fn a_keyframe_right_after_a_keyframe_goes_at_once() {
        let mut pacing = KeyframePacing::new();
        pacing.encoded(true);
        assert!(pacing.allows_key());
    }

    #[test]
    fn the_wait_grows_while_asked_again_and_ends_after_a_quiet_spell() {
        let mut pacing = KeyframePacing::new();
        pacing.encoded(true);
        for wait in 1..=3 {
            pacing.encoded(true);
            for _ in 0..wait {
                assert!(!pacing.allows_key());
                pacing.encoded(false);
            }
            assert!(pacing.allows_key());
        }
        for _ in 0..60 {
            pacing.encoded(false);
        }
        pacing.encoded(true);
        assert!(pacing.allows_key());
    }

    #[test]
    fn the_wait_stops_growing() {
        let mut pacing = KeyframePacing::new();
        pacing.encoded(true);
        for _ in 0..100 {
            while !pacing.allows_key() {
                pacing.encoded(false);
            }
            pacing.encoded(true);
        }
        for _ in 0..MOST_DELTAS_BETWEEN {
            assert!(!pacing.allows_key());
            pacing.encoded(false);
        }
        assert!(pacing.allows_key());
    }

    fn ms(start: Instant, ms: u64) -> Instant {
        start + Duration::from_millis(ms)
    }

    #[test]
    fn the_first_picture_is_a_keyframe() {
        assert!(Keyframes::new().next(Instant::now()));
    }

    #[test]
    fn a_viewer_waits_a_second_from_the_last_keyframe() {
        let start = Instant::now();
        let mut keys = Keyframes::new();
        keys.encoded(true, start);
        for at in [100, 400] {
            keys.encoded(false, ms(start, at));
        }
        keys.heard(KeyframeWanted::Viewer);
        assert!(!keys.next(ms(start, 500)));
        assert!(!keys.next(ms(start, 999)));
        assert!(keys.next(ms(start, 1_000)));
        keys.encoded(true, ms(start, 1_000));
        assert!(!keys.next(ms(start, 1_100)));
    }

    #[test]
    fn a_viewer_long_after_the_last_keyframe_gets_one_at_once() {
        let start = Instant::now();
        let mut keys = Keyframes::new();
        keys.encoded(true, start);
        keys.encoded(false, ms(start, 5_000));
        keys.heard(KeyframeWanted::Viewer);
        assert!(keys.next(ms(start, 5_010)));
    }

    #[test]
    fn mending_the_chain_does_not_wait() {
        let start = Instant::now();
        let mut keys = Keyframes::new();
        keys.encoded(true, start);
        keys.encoded(false, ms(start, 16));
        keys.heard(KeyframeWanted::Mend);
        assert!(keys.next(ms(start, 33)));
    }

    #[test]
    fn viewers_asking_all_the_time_get_one_keyframe_a_second() {
        let start = Instant::now();
        let mut keys = Keyframes::new();
        let mut made = 0;
        // 60 pictures a second for 10 s, a viewer asking before each.
        for picture in 0..600u64 {
            let at = ms(start, picture * 1000 / 60);
            keys.heard(KeyframeWanted::Viewer);
            let key = keys.next(at);
            keys.encoded(key, at);
            made += u32::from(key);
        }
        assert!((10..=11).contains(&made), "{made}");
    }
}
