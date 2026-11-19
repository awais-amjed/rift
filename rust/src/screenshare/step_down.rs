//! Stepping a GPU share down to what the connection carries, and back up.
//!
//! WebRTC lowers the size or frame rate of a picture it encodes itself, in the
//! order the Prioritise row asks for (`track.rs`). A GPU share reaches it
//! already encoded, so it cannot: the picture stays at its size and rate, and
//! only the bitrate falls. Below what that size needs, the encoder overshoots
//! and the rate gate leaves pictures out unevenly, and a keyframe, which a
//! viewer asks for on joining or on losing packets, shuts the gate for a
//! second or more (the Nov 18 2026 review, A2: a friend's RDR2 share at 0.3
//! to 2 Mbps showing 1 to 18 pictures a second).
//!
//! So when the gate keeps leaving pictures out, the share takes the next step
//! down its ladder: a smaller picture, which the encoder is opened again for
//! on the same track, or fewer pictures, an even share of those that come.
//! Which it gives up first follows the priority. Once WebRTC's target would
//! carry the step above, and has for a while, it climbs back; a climb that
//! fails makes the next one wait longer.
//!
//! Whether the gate leaves pictures out says whether the share fits, whatever
//! is on screen: a still desktop at a low rate keeps its size, since it costs
//! next to nothing. WebRTC's target says when to climb, since a share held
//! below it cannot show that more would fit.
//!
//! Neither says anything while nobody watches. The server pauses the picture
//! then, WebRTC's target stays where it was, low for a share started before
//! anybody came, and the gate went on leaving pictures out against it. A
//! 1440p share nobody watched on Windows 10 stepped down to 960p within 20 s,
//! and its first viewer waited 11 s for the full size (Nov 19 2026). So the
//! share holds its step while paused, and judges again once WebRTC's estimate
//! has had a few seconds with a viewer.

use super::resolution::Size;
use crate::api::screenshare::types::SharePriority;
use std::time::{Duration, Instant};

/// How long the pictures offered and left out are counted over before the
/// share is judged.
const WINDOW: Duration = Duration::from_secs(2);

/// The part of a window's pictures the gate may leave out before the window
/// counts against the step. A viewer joining at a healthy rate costs a few
/// pictures in a window: a keyframe several pictures' worth.
const LEFT_OUT_SHARE: f64 = 0.1;

/// Windows in a row against the step before the share goes down one.
const BAD_WINDOWS: u32 = 2;

/// The fewest pictures a window must have to be judged: a still screen sends
/// next to none, and says nothing about the connection. More than a refused
/// still picture is offered again in one (every 100 ms, `capture_wgc.rs` and
/// `capture_pw.rs`), since each try counts.
const FEWEST_PICTURES: u32 = 30;

/// How long after a step nothing is judged: the new encoder's first picture
/// is a keyframe, and the encoder's rate takes a second to follow fewer
/// pictures.
const SETTLE: Duration = Duration::from_secs(3);

/// How long after a track's first picture nothing is judged: WebRTC's
/// estimate starts at 1 Mbps and takes a few seconds to climb.
const START_SETTLE: Duration = Duration::from_secs(5);

/// What WebRTC's target must reach, in bits a second for each pixel of each
/// picture, before the share climbs to a step: 3.7 Mbps for 1080p at 60 fps,
/// about twice what that left nothing out at (`CALLS.md`). Or the share's
/// cap, which the target never passes.
const CLIMB_BITS_PER_PIXEL: f64 = 0.03;

/// How long the target must stay there before the share climbs.
const CLIMB_HOLD: Duration = Duration::from_secs(10);

/// A share that goes down again this soon after climbing climbed too early,
/// and waits twice as long next time, up to [`LONGEST_CLIMB_HOLD`]; one that
/// goes down later waits the usual time.
const FAILED_CLIMB: Duration = Duration::from_secs(60);
const LONGEST_CLIMB_HOLD: Duration = Duration::from_secs(160);

/// The fewest rows and columns a smaller picture is stepped down to: a tall,
/// narrow window keeps a width every encoder takes.
const LOWEST_HEIGHT: u32 = 360;
const LOWEST_WIDTH: u32 = 256;

/// The fewest pictures a second the share is stepped down to.
const LOWEST_FPS: u32 = 10;

/// Balanced halves the frame rate only from this rate up: 30 is already as
/// few as it gives up.
const BALANCED_HALVES_FROM: u32 = 50;

/// The smaller pictures, as a part of the full one's sides.
const SIZES: [(u32, u32); 4] = [(1, 1), (2, 3), (1, 2), (1, 3)];

/// One step of the ladder: the picture's sides times `num / den`, and one
/// picture in `fps_div` of the share's rate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Rung {
    num: u32,
    den: u32,
    fps_div: u32,
}

/// What a step changed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Change {
    /// Only the frame rate, which the feed puts into effect itself.
    Fps,
    /// The size, which takes an encoder opened again for it.
    Size,
}

/// A step taken, and from where to where, for the log.
#[derive(Debug)]
pub(crate) struct Stepped {
    pub change: Change,
    pub from: String,
    pub to: String,
}

/// Where a GPU share is on its ladder, and what it has seen there.
#[derive(Debug)]
pub(crate) struct StepDown {
    priority: SharePriority,
    /// The picture at the top of the ladder, as the share's settings ask.
    full: Size,
    fps: u32,
    /// The share's cap, in bits a second.
    cap_bps: u32,
    rungs: Vec<Rung>,
    at: usize,
    /// When the window began, and the pictures offered and left out in it.
    window: Option<(Instant, u32, u32)>,
    /// When the last window was judged: one that began much later does not
    /// follow it.
    judged: Option<Instant>,
    bad_windows: u32,
    /// Nothing is judged before this; until the first picture, not set.
    settled: Option<Instant>,
    /// Since when the target would carry the step above.
    climbable_since: Option<Instant>,
    climb_hold: Duration,
    climbed_at: Option<Instant>,
    /// When the next picture is due, while the frame rate is stepped down.
    due: Option<Instant>,
    /// Whether the server has paused the picture, nobody watching it.
    paused: bool,
}

impl StepDown {
    pub(crate) fn new(priority: SharePriority) -> StepDown {
        StepDown {
            priority,
            full: Size {
                width: 2,
                height: 2,
            },
            fps: 1,
            cap_bps: 0,
            rungs: vec![Rung {
                num: 1,
                den: 1,
                fps_div: 1,
            }],
            at: 0,
            window: None,
            judged: None,
            bad_windows: 0,
            settled: None,
            climbable_since: None,
            climb_hold: CLIMB_HOLD,
            climbed_at: None,
            due: None,
            paused: false,
        }
    }

    /// Take the picture the share's settings ask for, at the top of the
    /// ladder, and its cap. The share stays as far down as it was, or at the
    /// foot of a shorter ladder.
    pub(crate) fn fit(&mut self, full: Size, fps: u32, cap_bps: u32) {
        self.full = full;
        self.fps = fps.max(1);
        self.cap_bps = cap_bps;
        self.rungs = ladder(self.priority, full, self.fps);
        self.at = self.at.min(self.rungs.len() - 1);
    }

    /// The size to encode at, on this step.
    pub(crate) fn size(&self) -> Size {
        self.size_on(self.rungs[self.at])
    }

    /// The pictures a second sent, on this step.
    pub(crate) fn fps(&self) -> u32 {
        self.fps / self.rungs[self.at].fps_div
    }

    /// Whether a picture coming `now` is one of those this step sends: all of
    /// them at the share's own rate, and an even share of them below it. One
    /// that is not never reaches the rate gate.
    pub(crate) fn takes(&mut self, now: Instant) -> bool {
        let div = self.rungs[self.at].fps_div;
        if div == 1 {
            self.due = None;
            return true;
        }
        let interval = Duration::from_secs_f64(f64::from(div) / f64::from(self.fps));
        match self.due {
            // A picture a little early is taken: pictures come unevenly, and
            // waiting for the next would make it a whole picture late.
            Some(due) if now + interval / 4 < due => false,
            due => {
                // On time, the next is due an interval after this one was;
                // after a gap, an interval from now, or the next picture to
                // come would go straight after it.
                self.due = Some(match due {
                    Some(due) if now < due + interval => due + interval,
                    _ => now + interval,
                });
                true
            }
        }
    }

    /// Note whether the server has paused the picture, and say whether that
    /// changed. Paused, nothing is judged; watched again, the share waits as
    /// a new track does, for WebRTC's estimate to climb.
    pub(crate) fn set_paused(&mut self, paused: bool, now: Instant) -> bool {
        if paused == self.paused {
            return false;
        }
        self.paused = paused;
        self.window = None;
        self.judged = None;
        self.bad_windows = 0;
        self.climbable_since = None;
        if !paused && self.settled.is_some() {
            self.settled = Some(now + START_SETTLE);
        }
        true
    }

    /// Note a picture the gate admitted or left out, at what WebRTC asks for,
    /// and say whether the share steps down or up for it.
    pub(crate) fn picture(
        &mut self,
        admitted: bool,
        target_bps: u32,
        now: Instant,
    ) -> Option<Stepped> {
        if now < *self.settled.get_or_insert(now + START_SETTLE) || self.paused {
            return None;
        }
        if self.at > 0 && f64::from(target_bps) >= self.climb_needs() {
            let since = *self.climbable_since.get_or_insert(now);
            if now.duration_since(since) >= self.climb_hold {
                return Some(self.step_to(self.at - 1, now));
            }
        } else {
            self.climbable_since = None;
        }
        let (start, offered, left_out) = self.window.get_or_insert((now, 0, 0));
        *offered += 1;
        if !admitted {
            *left_out += 1;
        }
        let span = now.duration_since(*start);
        if span < WINDOW {
            return None;
        }
        // A window that ran on through a still spell is not two seconds of
        // anything.
        let bad = span < WINDOW * 3 / 2
            && *offered >= FEWEST_PICTURES
            && f64::from(*left_out) > LEFT_OUT_SHARE * f64::from(*offered);
        let follows = self
            .judged
            .is_some_and(|judged| start.duration_since(judged) < WINDOW / 2);
        self.window = None;
        self.judged = Some(now);
        if !bad {
            self.bad_windows = 0;
            return None;
        }
        self.bad_windows = if follows { self.bad_windows + 1 } else { 1 };
        self.climbable_since = None;
        if self.bad_windows < BAD_WINDOWS || self.at + 1 == self.rungs.len() {
            return None;
        }
        self.climb_hold = if self
            .climbed_at
            .take()
            .is_some_and(|climbed| now.duration_since(climbed) < FAILED_CLIMB)
        {
            (self.climb_hold * 2).min(LONGEST_CLIMB_HOLD)
        } else {
            CLIMB_HOLD
        };
        Some(self.step_to(self.at + 1, now))
    }

    /// This step, for the log: "1280x720 at 60 fps".
    pub(crate) fn describe(&self) -> String {
        let size = self.size();
        format!("{}x{} at {} fps", size.width, size.height, self.fps())
    }

    fn step_to(&mut self, to: usize, now: Instant) -> Stepped {
        let from = self.rungs[self.at];
        let described = self.describe();
        if to < self.at {
            self.climbed_at = Some(now);
        }
        self.at = to;
        self.window = None;
        self.judged = None;
        self.bad_windows = 0;
        self.climbable_since = None;
        self.settled = Some(now + SETTLE);
        Stepped {
            change: if self.size_on(from) == self.size() {
                Change::Fps
            } else {
                Change::Size
            },
            from: described,
            to: self.describe(),
        }
    }

    fn size_on(&self, rung: Rung) -> Size {
        let side = |pixels: u32| even_floor(pixels * rung.num / rung.den);
        Size {
            width: side(self.full.width),
            height: side(self.full.height),
        }
    }

    /// What WebRTC's target must be to climb a step, in bits a second.
    fn climb_needs(&self) -> f64 {
        let rung = self.rungs[self.at - 1];
        let size = self.size_on(rung);
        let needs = f64::from(size.width)
            * f64::from(size.height)
            * f64::from(self.fps / rung.fps_div)
            * CLIMB_BITS_PER_PIXEL;
        if self.cap_bps > 0 {
            needs.min(f64::from(self.cap_bps))
        } else {
            needs
        }
    }
}

/// The steps a share at `height` rows and `fps` takes down, in order:
/// Smoothness gives up size, Sharpness frame rate, and Balanced the first
/// smaller size, then half the frame rate, then size again.
fn ladder(priority: SharePriority, full: Size, fps: u32) -> Vec<Rung> {
    let sizes: Vec<(u32, u32)> = SIZES
        .iter()
        .copied()
        .enumerate()
        .filter(|&(i, (num, den))| {
            i == 0
                || (full.height * num / den >= LOWEST_HEIGHT
                    && full.width * num / den >= LOWEST_WIDTH)
        })
        .map(|(_, size)| size)
        .collect();
    let rung = |(num, den): (u32, u32), fps_div| Rung { num, den, fps_div };
    match priority {
        SharePriority::Smoothness => sizes.iter().map(|&size| rung(size, 1)).collect(),
        SharePriority::Sharpness => (1..=3)
            .filter(|&div| div == 1 || fps / div >= LOWEST_FPS)
            .map(|div| rung((1, 1), div))
            .collect(),
        SharePriority::Balanced => {
            let mut rungs = vec![rung(sizes[0], 1)];
            if let Some(&first_smaller) = sizes.get(1) {
                rungs.push(rung(first_smaller, 1));
            }
            let div = if fps >= BALANCED_HALVES_FROM { 2 } else { 1 };
            if div == 2 {
                rungs.push(rung(*sizes.get(1).unwrap_or(&sizes[0]), div));
            }
            rungs.extend(sizes.iter().skip(2).map(|&size| rung(size, div)));
            rungs
        }
    }
}

fn even_floor(value: u32) -> u32 {
    (value & !1).max(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FULL: Size = Size {
        width: 1920,
        height: 1080,
    };

    fn sizes_and_rates(step: &mut StepDown) -> Vec<String> {
        let mut seen = vec![step.describe()];
        while step.at + 1 < step.rungs.len() {
            step.at += 1;
            seen.push(step.describe());
        }
        seen
    }

    const CAP: u32 = 8_000_000;

    /// A share fitted to 1080p60, past its first settling.
    fn fitted(priority: SharePriority) -> StepDown {
        let mut step = StepDown::new(priority);
        step.fit(FULL, 60, CAP);
        step.settled = Some(Instant::now());
        step
    }

    #[test]
    fn each_priority_gives_up_its_own_thing() {
        assert_eq!(
            sizes_and_rates(&mut fitted(SharePriority::Smoothness)),
            [
                "1920x1080 at 60 fps",
                "1280x720 at 60 fps",
                "960x540 at 60 fps",
                "640x360 at 60 fps"
            ]
        );
        assert_eq!(
            sizes_and_rates(&mut fitted(SharePriority::Sharpness)),
            [
                "1920x1080 at 60 fps",
                "1920x1080 at 30 fps",
                "1920x1080 at 20 fps"
            ]
        );
        assert_eq!(
            sizes_and_rates(&mut fitted(SharePriority::Balanced)),
            [
                "1920x1080 at 60 fps",
                "1280x720 at 60 fps",
                "1280x720 at 30 fps",
                "960x540 at 30 fps",
                "640x360 at 30 fps"
            ]
        );
    }

    #[test]
    fn a_small_or_slow_share_has_a_short_ladder() {
        let mut step = StepDown::new(SharePriority::Balanced);
        step.fit(
            Size {
                width: 854,
                height: 480,
            },
            30,
            CAP,
        );
        assert_eq!(sizes_and_rates(&mut step), ["854x480 at 30 fps"]);
        let mut step = StepDown::new(SharePriority::Sharpness);
        step.fit(FULL, 15, CAP);
        assert_eq!(sizes_and_rates(&mut step), ["1920x1080 at 15 fps"]);
        // A tall, narrow window: 2/3 of 300 columns is too narrow to encode.
        let mut step = StepDown::new(SharePriority::Smoothness);
        step.fit(
            Size {
                width: 300,
                height: 1080,
            },
            60,
            CAP,
        );
        assert_eq!(sizes_and_rates(&mut step), ["300x1080 at 60 fps"]);
    }

    /// Offer `seconds` of pictures at 60 a second, each admitted by
    /// `admitted(n)` at `target`, from `start`; say what changed and when.
    fn run(
        step: &mut StepDown,
        start: Instant,
        seconds: f64,
        target: u32,
        admitted: impl Fn(u32) -> bool,
    ) -> Vec<(f64, Change)> {
        let mut changes = vec![];
        for n in 0..(seconds * 60.0) as u32 {
            let at = f64::from(n) / 60.0;
            let now = start + Duration::from_secs_f64(at);
            if !step.takes(now) {
                continue;
            }
            if let Some(stepped) = step.picture(admitted(n), target, now) {
                changes.push((at, stepped.change));
            }
        }
        changes
    }

    #[test]
    fn a_share_that_fits_stays_where_it_is() {
        let mut step = fitted(SharePriority::Smoothness);
        assert_eq!(
            run(&mut step, Instant::now(), 60.0, 1_000_000, |_| true),
            []
        );
        assert_eq!(step.at, 0);
    }

    #[test]
    fn a_keyframe_now_and_then_is_not_a_reason_to_step_down() {
        let mut step = fitted(SharePriority::Smoothness);
        // Six pictures left out after a keyframe every five seconds.
        let changes = run(&mut step, Instant::now(), 60.0, 1_000_000, |n| n % 300 >= 6);
        assert_eq!(changes, []);
    }

    #[test]
    fn a_share_leaving_pictures_out_steps_down_after_two_windows() {
        let mut step = fitted(SharePriority::Smoothness);
        // Every other picture left out, at a rate that carries nothing bigger.
        let changes = run(&mut step, Instant::now(), 5.0, 1_000_000, |n| n % 2 == 0);
        assert_eq!(changes.len(), 1, "{changes:?}");
        let (at, change) = changes[0];
        assert!((4.0..4.2).contains(&at), "{at}");
        assert_eq!(change, Change::Size);
        assert_eq!(step.describe(), "1280x720 at 60 fps");
    }

    #[test]
    fn it_waits_after_a_step_and_goes_on_down_if_it_must() {
        let mut step = fitted(SharePriority::Smoothness);
        let changes = run(&mut step, Instant::now(), 30.0, 500_000, |n| n % 2 == 0);
        let at: Vec<_> = changes.iter().map(|&(at, _)| at.round() as u32).collect();
        // Two windows, then three seconds to settle and two windows more.
        assert_eq!(at, [4, 11, 18], "{changes:?}");
        assert_eq!(step.describe(), "640x360 at 60 fps");
    }

    #[test]
    fn a_still_screen_is_not_judged() {
        let mut step = fitted(SharePriority::Smoothness);
        let start = Instant::now();
        // A refused picture offered again every 100 ms, every try left out.
        for n in 0..600u32 {
            let now = start + Duration::from_millis(u64::from(n) * 100);
            assert!(step.picture(false, 300_000, now).is_none());
        }
    }

    #[test]
    fn fewer_pictures_are_an_even_share_of_those_that_come() {
        let mut step = fitted(SharePriority::Sharpness);
        step.at = 1;
        let start = Instant::now();
        let mut taken = vec![];
        for n in 0..60u32 {
            // A picture every 16.7 ms, give or take 3.
            let jitter = [0i64, 3, -3, 2][n as usize % 4];
            let at = (i64::from(n) * 16_667 + jitter * 1000).max(0) as u64;
            if step.takes(start + Duration::from_micros(at)) {
                taken.push(n);
            }
        }
        assert_eq!(taken.len(), 30, "{taken:?}");
        assert!(
            taken.windows(2).all(|pair| pair[1] - pair[0] == 2),
            "{taken:?}"
        );
    }

    #[test]
    fn after_a_gap_the_next_picture_is_a_whole_interval_on() {
        let mut step = fitted(SharePriority::Sharpness);
        step.at = 1;
        let start = Instant::now();
        let at = |ms: u64| start + Duration::from_millis(ms);
        assert!(step.takes(at(0)));
        // Half a second still, then pictures every 16.7 ms again.
        assert!(step.takes(at(500)));
        assert!(!step.takes(at(517)));
        assert!(step.takes(at(533)));
    }

    #[test]
    fn a_new_track_is_not_judged_while_its_rate_climbs() {
        let mut step = StepDown::new(SharePriority::Smoothness);
        step.fit(FULL, 60, CAP);
        let changes = run(&mut step, Instant::now(), 9.5, 1_000_000, |n| n % 2 == 0);
        // Five seconds to settle, then two windows.
        assert_eq!(changes.len(), 1, "{changes:?}");
        assert!((9.0..9.2).contains(&changes[0].0), "{changes:?}");
    }

    #[test]
    fn bad_windows_far_apart_do_not_add_up() {
        let mut step = fitted(SharePriority::Smoothness);
        let start = Instant::now();
        // A bad stretch of two seconds, a minute of a still screen, and
        // another.
        assert_eq!(run(&mut step, start, 2.1, 1_000_000, |n| n % 2 == 0), []);
        let later = start + Duration::from_secs(60);
        assert_eq!(run(&mut step, later, 2.1, 1_000_000, |n| n % 2 == 0), []);
        assert_eq!(step.at, 0);
    }

    #[test]
    fn a_share_capped_under_what_the_step_above_needs_climbs_at_its_cap() {
        let mut step = StepDown::new(SharePriority::Smoothness);
        step.fit(FULL, 60, 3_000_000);
        step.settled = Some(Instant::now());
        let start = Instant::now();
        run(&mut step, start, 5.0, 1_000_000, |n| n % 2 == 0);
        assert_eq!(step.at, 1);
        let later = start + Duration::from_secs(5);
        let changes = run(&mut step, later, 15.0, 3_000_000, |_| true);
        assert_eq!(changes.len(), 1, "{changes:?}");
        assert_eq!(step.at, 0);
    }

    #[test]
    fn it_climbs_back_once_the_target_carries_the_step_above() {
        let mut step = fitted(SharePriority::Smoothness);
        let start = Instant::now();
        run(&mut step, start, 5.0, 1_000_000, |n| n % 2 == 0);
        assert_eq!(step.describe(), "1280x720 at 60 fps");
        // 1080p at 60 fps needs 3.7 Mbps: 3 does not climb, 4 does after the
        // hold.
        let later = start + Duration::from_secs(5);
        assert_eq!(run(&mut step, later, 30.0, 3_000_000, |_| true), []);
        let later = later + Duration::from_secs(30);
        let changes = run(&mut step, later, 15.0, 4_000_000, |_| true);
        assert_eq!(changes.len(), 1, "{changes:?}");
        assert!((9.9..10.1).contains(&changes[0].0), "{changes:?}");
        assert_eq!(step.at, 0);
    }

    #[test]
    fn a_climb_that_fails_makes_the_next_wait_longer() {
        let mut step = fitted(SharePriority::Smoothness);
        let start = Instant::now();
        run(&mut step, start, 5.0, 1_000_000, |n| n % 2 == 0);
        let at = |seconds| start + Duration::from_secs(seconds);
        assert_eq!(run(&mut step, at(5), 15.0, 4_000_000, |_| true).len(), 1);
        assert_eq!(step.at, 0);
        // Straight back down after climbing.
        let down = run(&mut step, at(20), 5.0, 4_000_000, |n| n % 2 == 0);
        assert_eq!(down.len(), 1, "{down:?}");
        assert_eq!(step.climb_hold, CLIMB_HOLD * 2);
        let up = run(&mut step, at(28), 30.0, 4_000_000, |_| true);
        assert_eq!(up.len(), 1, "{up:?}");
        assert!((19.9..20.1).contains(&up[0].0), "{up:?}");
    }

    #[test]
    fn a_share_nobody_watches_holds_its_size() {
        let mut step = fitted(SharePriority::Smoothness);
        let start = Instant::now();
        assert!(step.set_paused(true, start));
        assert!(!step.set_paused(true, start), "no change");
        // A low target from before anybody came, and every other picture
        // left out against it.
        assert_eq!(run(&mut step, start, 30.0, 800_000, |n| n % 2 == 0), []);
        assert_eq!(step.at, 0);
    }

    #[test]
    fn a_paused_share_neither_climbs_nor_finishes_a_window() {
        let mut step = fitted(SharePriority::Smoothness);
        let start = Instant::now();
        run(&mut step, start, 5.0, 1_000_000, |n| n % 2 == 0);
        assert_eq!(step.at, 1);
        let at = |seconds| start + Duration::from_secs(seconds);
        // One bad window before the pause does not add to one after it.
        assert_eq!(run(&mut step, at(10), 2.1, 1_000_000, |n| n % 2 == 0), []);
        step.set_paused(true, at(13));
        assert_eq!(run(&mut step, at(13), 30.0, 4_000_000, |_| true), [], "no climb");
        assert_eq!(step.at, 1);
        step.set_paused(false, at(43));
        // Five seconds for the estimate, then two windows.
        let changes = run(&mut step, at(43), 9.5, 1_000_000, |n| n % 2 == 0);
        assert_eq!(changes.len(), 1, "{changes:?}");
        assert!((9.0..9.2).contains(&changes[0].0), "{changes:?}");
    }

    #[test]
    fn a_new_setting_keeps_the_step_within_the_ladder() {
        let mut step = fitted(SharePriority::Smoothness);
        step.at = 3;
        step.fit(
            Size {
                width: 1280,
                height: 720,
            },
            60,
            CAP,
        );
        assert_eq!(step.describe(), "640x360 at 60 fps");
    }
}
