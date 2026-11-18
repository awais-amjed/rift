//! A game in exclusive full screen, for a Windows share of its window.
//!
//! Windows Graphics Capture takes a window's pictures from the compositor, and
//! a game in exclusive full screen draws past it: a session on its window gives
//! a first picture and then nothing. A quiet session is replaced every 2 s
//! (`capture_wgc::QUIET_FOR`), so the share went on as one picture each 2 s,
//! never counted as failed, and the sharer was not told (the review of a
//! friend's RDR2 share, Nov 18 2026). A still window goes quiet the same way,
//! having nothing to draw, so a run of quiet sessions alone says nothing. It
//! says "exclusive full screen" when the window is in front and fills its
//! screen, and Windows says a Direct3D program has the screen to itself or a
//! game holds the mouse. Then the sharer is told, once a share, to set the game
//! to borderless or share the screen. Sharing the screen in its place was left
//! out: a window was chosen, and the screen shows whatever is in front of the
//! game after an Alt+Tab.
use std::cell::Cell;
use std::time::{Duration, Instant};

use super::game_mouse::Rect;

/// A new session opened within this of the last one goes on the same run. On a
/// still source they come every 2 s, or every 2 s after a picture.
const RUN_GAP: Duration = Duration::from_secs(5);

/// New sessions in a run before the window is looked at, about 6 s of no
/// pictures.
const LOOK_AFTER: u32 = 3;

/// Looks in a row that must find a game before the sharer is told, which puts
/// it about 10 s after the pictures stopped: a game loading a level, or paused,
/// can draw nothing for a few seconds. It is still before a share whose new
/// sessions give nothing at all hands over to libwebrtc's capturer, at 12 s.
const LOOKS: u32 = 3;

thread_local! {
    /// Whether this share's sharer has been told. A share keeps one capture
    /// thread for its life, through each hand-over to libwebrtc's capturer and
    /// back, each of which starts a new [`QuietRun`].
    static TOLD: Cell<bool> = const { Cell::new(false) };
}

/// What a new session on a quiet source calls for.
#[derive(Debug, PartialEq)]
pub(crate) enum Run {
    /// Look at the window, and tell [`QuietRun::looked`] what was found.
    /// `first` of this run, which is logged.
    Look {
        first: bool,
    },
    Nothing,
}

/// Counts the new sessions a share opens on a quiet source, run by run.
pub(crate) struct QuietRun {
    count: u32,
    last: Option<Instant>,
    /// Looks in a row that found a game.
    found: u32,
    told: bool,
}

impl QuietRun {
    pub(crate) fn new() -> Self {
        Self {
            count: 0,
            last: None,
            found: 0,
            told: TOLD.get(),
        }
    }

    /// A new session opened at `now`.
    pub(crate) fn reopened(&mut self, now: Instant) -> Run {
        let goes_on = self
            .last
            .is_some_and(|last| now.duration_since(last) <= RUN_GAP);
        if !goes_on {
            self.count = 0;
            self.found = 0;
        }
        self.count += 1;
        self.last = Some(now);
        if self.count >= LOOK_AFTER && !self.told {
            Run::Look {
                first: self.count == LOOK_AFTER,
            }
        } else {
            Run::Nothing
        }
    }

    /// What a look found. True when the sharer is to be told now, which is
    /// once a share.
    pub(crate) fn looked(&mut self, game: bool) -> bool {
        self.found = if game { self.found + 1 } else { 0 };
        if self.found < LOOKS {
            return false;
        }
        self.told = true;
        TOLD.set(true);
        true
    }
}

/// What a look at the shared window found.
#[derive(Debug)]
pub(crate) struct Seen {
    /// In front and covering its whole screen, as exclusive full screen is.
    pub fills_front: bool,
    /// Windows says a Direct3D program has the screen to itself.
    pub d3d: bool,
    /// A game has locked the mouse inside its window (`game_mouse`), which
    /// only tells on a desktop of more than one screen.
    pub mouse: bool,
}

impl Seen {
    pub(crate) fn game(&self) -> bool {
        self.fills_front && (self.d3d || self.mouse)
    }
}

/// Whether a window covers the whole of its screen.
pub(crate) fn fills(window: Rect, screen: Rect) -> bool {
    screen.within(&window)
}

/// A look at the window `id` now.
#[cfg(target_os = "windows")]
pub(crate) fn look(id: u64) -> Seen {
    use windows::Win32::Foundation::{HWND, RECT};
    use windows::Win32::Graphics::Gdi::{
        GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTONULL,
    };
    use windows::Win32::UI::Shell::{SHQueryUserNotificationState, QUNS_RUNNING_D3D_FULL_SCREEN};
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowRect};

    let of = |r: RECT| Rect {
        left: r.left,
        top: r.top,
        right: r.right,
        bottom: r.bottom,
    };
    let window = HWND(id as usize as *mut _);
    // SAFETY: each call writes only what it is handed, which outlives it; a
    // closed window only makes them fail.
    let fills_front = unsafe {
        let mut rect = RECT::default();
        let monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
        let mut info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        GetForegroundWindow() == window
            && GetWindowRect(window, &mut rect).is_ok()
            && !monitor.is_invalid()
            && GetMonitorInfoW(monitor, &mut info).as_bool()
            && fills(of(rect), of(info.rcMonitor))
    };
    // SAFETY: no arguments; it only answers.
    let d3d = unsafe { SHQueryUserNotificationState() }
        .is_ok_and(|state| state == QUNS_RUNNING_D3D_FULL_SCREEN);
    Seen {
        fills_front,
        d3d,
        mouse: super::game_mouse::game_holds_mouse(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(start: Instant, ms: u64) -> Instant {
        start + Duration::from_millis(ms)
    }

    #[test]
    fn three_looks_in_a_row_tell_the_sharer_once() {
        let start = Instant::now();
        let mut run = QuietRun::new();
        assert_eq!(run.reopened(at(start, 2_000)), Run::Nothing);
        assert_eq!(run.reopened(at(start, 4_050)), Run::Nothing);
        assert_eq!(run.reopened(at(start, 6_100)), Run::Look { first: true });
        assert!(!run.looked(true));
        assert_eq!(run.reopened(at(start, 8_150)), Run::Look { first: false });
        assert!(!run.looked(true));
        assert_eq!(run.reopened(at(start, 10_200)), Run::Look { first: false });
        assert!(run.looked(true));
        assert_eq!(run.reopened(at(start, 12_250)), Run::Nothing);
        // A hand-over and back starts a new count on the same thread, and
        // the share has been told.
        let mut back = QuietRun::new();
        for ms in [20_000, 22_000, 24_000, 26_000] {
            assert_eq!(back.reopened(at(start, ms)), Run::Nothing);
        }
    }

    #[test]
    fn a_look_that_finds_no_game_starts_the_count_again() {
        let start = Instant::now();
        let mut run = QuietRun::new();
        run.reopened(at(start, 2_000));
        run.reopened(at(start, 4_000));
        let mut told = vec![];
        for (i, game) in [true, true, false, true, true, true]
            .into_iter()
            .enumerate()
        {
            assert!(matches!(
                run.reopened(at(start, 6_000 + 2_000 * i as u64)),
                Run::Look { .. }
            ));
            told.push(run.looked(game));
        }
        assert_eq!(told, [false, false, false, false, false, true]);
    }

    #[test]
    fn pictures_between_sessions_start_a_new_run() {
        let start = Instant::now();
        let mut run = QuietRun::new();
        run.reopened(at(start, 2_000));
        run.reopened(at(start, 4_000));
        assert_eq!(run.reopened(at(start, 6_000)), Run::Look { first: true });
        assert!(!run.looked(true));
        assert_eq!(run.reopened(at(start, 8_000)), Run::Look { first: false });
        assert!(!run.looked(true));
        // Pictures came for a while, then stopped again: three new looks.
        assert_eq!(run.reopened(at(start, 20_000)), Run::Nothing);
        assert_eq!(run.reopened(at(start, 22_000)), Run::Nothing);
        assert_eq!(run.reopened(at(start, 24_000)), Run::Look { first: true });
        assert!(!run.looked(true));
        run.reopened(at(start, 26_000));
        assert!(!run.looked(true));
        run.reopened(at(start, 28_000));
        assert!(run.looked(true));
    }

    #[test]
    fn a_game_fills_its_screen_in_front_and_holds_it() {
        let seen = |fills_front, d3d, mouse| Seen {
            fills_front,
            d3d,
            mouse,
        };
        assert!(seen(true, true, false).game());
        assert!(seen(true, false, true).game());
        assert!(!seen(true, false, false).game());
        assert!(!seen(false, true, true).game());
    }

    #[test]
    fn a_window_fills_its_screen_only_to_every_edge() {
        let screen = Rect {
            left: 1920,
            top: 0,
            right: 3840,
            bottom: 1080,
        };
        assert!(fills(screen, screen));
        // A borderless game window often hangs a pixel or more past the edges.
        let past = Rect {
            left: 1912,
            top: -8,
            right: 3848,
            bottom: 1088,
        };
        assert!(fills(past, screen));
        // A maximised window stops at the taskbar.
        let maximised = Rect {
            bottom: 1040,
            ..screen
        };
        assert!(!fills(maximised, screen));
    }
}
