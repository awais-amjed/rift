//! Whether a game has the mouse, for a Windows share of a whole screen.
//!
//! A game steered by the mouse locks it inside its own window (`ClipCursor`)
//! and hides it there, leaving it still or snapping it back to the middle.
//! Nobody sees it on the screen, but a capture of the screen draws the cursor
//! all the same: viewers saw a still arrow in the middle of a game (Nov 14
//! 2026). A share of the game's window does not. So while the mouse is held
//! like that, a whole-screen share leaves the cursor out, and puts it back as
//! soon as it is let go: Alt+Tab, or a menu that frees it.
use std::time::{Duration, Instant};

/// How often the hold is looked at. Leaving the game is noticed within this,
/// and a look is three calls into Windows.
const EVERY: Duration = Duration::from_millis(250);

/// A rectangle in desktop pixels, right and bottom outside it, as Windows
/// gives one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Rect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

impl Rect {
    fn within(&self, outer: &Rect) -> bool {
        self.left >= outer.left
            && self.top >= outer.top
            && self.right <= outer.right
            && self.bottom <= outer.bottom
    }
}

/// Whether the mouse is held the way a game holds it: kept to less than the
/// desktop, and inside the window in front, which is the one holding it.
pub(crate) fn held_by_game(clip: Rect, desktop: Rect, front: Option<Rect>) -> bool {
    !desktop.within(&clip) && front.is_some_and(|front| clip.within(&front))
}

/// Follows the hold for a share, saying when the cursor should go out or come
/// back.
pub(crate) struct CursorGate {
    shown: bool,
    next: Instant,
}

impl CursorGate {
    /// `held`: whether a game has the mouse as the share starts.
    pub(crate) fn new(held: bool, now: Instant) -> Self {
        Self {
            shown: !held,
            next: now + EVERY,
        }
    }

    pub(crate) fn shown(&self) -> bool {
        self.shown
    }

    /// Looks at the hold through `held`, no more often than [`EVERY`].
    /// Whether the cursor is now shown, when that has changed.
    pub(crate) fn step(&mut self, now: Instant, held: impl FnOnce() -> bool) -> Option<bool> {
        if now < self.next {
            return None;
        }
        self.next = now + EVERY;
        let shown = !held();
        (shown != self.shown).then(|| {
            self.shown = shown;
            if shown {
                log::info!("capture: the mouse is free again; the cursor is back in the share");
            } else {
                log::info!("capture: a game has locked the mouse; the cursor is left out");
            }
            shown
        })
    }
}

/// Whether a game has the mouse now.
#[cfg(target_os = "windows")]
pub(crate) fn game_holds_mouse() -> bool {
    use windows::Win32::Foundation::RECT;
    use windows::Win32::UI::WindowsAndMessaging::{
        GetClipCursor, GetForegroundWindow, GetSystemMetrics, GetWindowRect, SM_CXVIRTUALSCREEN,
        SM_CYVIRTUALSCREEN, SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN,
    };
    let of = |r: RECT| Rect {
        left: r.left,
        top: r.top,
        right: r.right,
        bottom: r.bottom,
    };
    let mut clip = RECT::default();
    // SAFETY: each call writes only the RECT it is handed, which outlives it.
    unsafe {
        if GetClipCursor(&mut clip).is_err() {
            return false;
        }
        let (x, y) = (
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
        );
        let desktop = Rect {
            left: x,
            top: y,
            right: x + GetSystemMetrics(SM_CXVIRTUALSCREEN),
            bottom: y + GetSystemMetrics(SM_CYVIRTUALSCREEN),
        };
        let window = GetForegroundWindow();
        let mut front = RECT::default();
        let front =
            (!window.0.is_null() && GetWindowRect(window, &mut front).is_ok()).then(|| of(front));
        held_by_game(of(clip), desktop, front)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(left: i32, top: i32, right: i32, bottom: i32) -> Rect {
        Rect {
            left,
            top,
            right,
            bottom,
        }
    }

    /// Two 1080p monitors side by side.
    const DESKTOP: Rect = Rect {
        left: 0,
        top: 0,
        right: 3840,
        bottom: 1080,
    };
    const GAME: Rect = Rect {
        left: 0,
        top: 0,
        right: 1920,
        bottom: 1080,
    };

    #[test]
    fn a_free_mouse_is_no_game_s() {
        assert!(!held_by_game(DESKTOP, DESKTOP, Some(GAME)));
    }

    #[test]
    fn a_mouse_kept_to_the_window_in_front_is_held() {
        assert!(held_by_game(GAME, DESKTOP, Some(GAME)));
        // Kept to one point in its middle, as some games keep it.
        assert!(held_by_game(rect(960, 540, 961, 541), DESKTOP, Some(GAME)));
        // A game in a window, kept to inside its frame.
        let window = rect(100, 100, 1380, 860);
        assert!(held_by_game(
            rect(108, 131, 1372, 852),
            DESKTOP,
            Some(window)
        ));
    }

    #[test]
    fn a_mouse_kept_outside_the_window_in_front_is_not() {
        assert!(!held_by_game(
            GAME,
            DESKTOP,
            Some(rect(1920, 0, 3840, 1080))
        ));
        assert!(!held_by_game(GAME, DESKTOP, None));
    }

    #[test]
    fn the_gate_changes_only_on_a_change_and_not_too_often() {
        let start = Instant::now();
        let mut gate = CursorGate::new(false, start);
        assert!(gate.shown());
        assert_eq!(gate.step(start, || true), None, "too soon to look");
        assert_eq!(gate.step(start + EVERY, || true), Some(false));
        assert!(!gate.shown());
        assert_eq!(gate.step(start + EVERY * 2, || true), None, "no change");
        assert_eq!(gate.step(start + EVERY * 3, || false), Some(true));
        assert!(gate.shown());
    }

    #[test]
    fn a_share_started_in_a_game_starts_without_the_cursor() {
        assert!(!CursorGate::new(true, Instant::now()).shown());
    }
}
