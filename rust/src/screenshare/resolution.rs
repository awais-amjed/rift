//! The one place the outgoing frame size is decided.
//!
//! Both the session (which sizes the video source) and the processing thread
//! (which scales frames into it) need this number, and they must agree: a
//! source created at one size and fed frames at another is a silent black
//! tile. So it is a pure function with no LiveKit types, and it has tests.

/// A frame size in pixels.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Size {
    pub width: u32,
    pub height: u32,
}

/// The size to publish for a `native` capture, capped at `max_height` rows.
///
/// Aspect ratio is kept; both sides are then rounded *down* to even because
/// I420 stores chroma at half resolution and every encoder wants even
/// dimensions. Rounding up would exceed the cap by a row.
pub fn target_size(native: Size, max_height: u32) -> Size {
    if native.width == 0 || native.height == 0 {
        return Size {
            width: 2,
            height: 2,
        };
    }
    let height = max_height.min(native.height).max(2);
    let width = (height as f64 * native.width as f64 / native.height as f64).round() as u32;
    Size {
        width: even_floor(width.max(2)),
        height: even_floor(height),
    }
}

/// `size` scaled down to fit inside `max`, aspect kept and both sides even,
/// or `size` itself when it already fits.
pub fn fit_within(size: Size, max: Size) -> Size {
    if size.width <= max.width && size.height <= max.height {
        return size;
    }
    let scale = (max.width as f64 / size.width as f64).min(max.height as f64 / size.height as f64);
    Size {
        width: even_floor(((size.width as f64 * scale).round() as u32).clamp(2, max.width)),
        height: even_floor(((size.height as f64 * scale).round() as u32).clamp(2, max.height)),
    }
}

fn even_floor(n: u32) -> u32 {
    n & !1
}

#[cfg(test)]
mod tests {
    use super::*;

    fn size(width: u32, height: u32) -> Size {
        Size { width, height }
    }

    #[test]
    fn native_below_cap_is_unchanged() {
        assert_eq!(target_size(size(1920, 1080), 1440), size(1920, 1080));
    }

    #[test]
    fn native_above_cap_scales_keeping_aspect() {
        assert_eq!(target_size(size(3840, 2160), 1080), size(1920, 1080));
        assert_eq!(target_size(size(2560, 1440), 720), size(1280, 720));
    }

    #[test]
    fn odd_results_round_down_to_even() {
        // 1080 * 1366 / 768 = 1920.9 -> 1921 -> 1920
        assert_eq!(target_size(size(1366, 768), 1080), size(1366, 768));
        assert_eq!(target_size(size(1367, 769), 1080), size(1366, 768));
        assert_eq!(target_size(size(1001, 1001), 1001), size(1000, 1000));
    }

    #[test]
    fn never_exceeds_the_cap() {
        for h in [2, 480, 719, 720, 1079, 1080, 2161] {
            assert!(target_size(size(9999, 5555), h).height <= h.max(2));
        }
    }

    #[test]
    fn a_size_that_fits_is_left_alone() {
        let max = size(4096, 2304);
        assert_eq!(fit_within(size(3840, 2160), max), size(3840, 2160));
        assert_eq!(fit_within(size(4096, 2304), max), size(4096, 2304));
    }

    #[test]
    fn a_super_ultrawide_screen_is_scaled_to_the_widest_allowed() {
        let max = size(4096, 2304);
        assert_eq!(fit_within(size(5120, 1440), max), size(4096, 1152));
        assert_eq!(fit_within(size(5120, 2880), max), size(4096, 2304));
        assert_eq!(fit_within(size(7680, 2160), max), size(4096, 1152));
    }

    #[test]
    fn a_tall_picture_is_held_to_the_height() {
        assert_eq!(
            fit_within(size(1440, 5120), size(4096, 2304)),
            size(648, 2304)
        );
    }

    #[test]
    fn a_fitted_size_stays_even_and_inside() {
        let max = size(4096, 2304);
        let fitted = fit_within(size(5119, 1439), max);
        assert_eq!((fitted.width % 2, fitted.height % 2), (0, 0));
        assert!(fitted.width <= max.width && fitted.height <= max.height);
    }

    #[test]
    fn degenerate_input_yields_a_legal_frame() {
        assert_eq!(target_size(size(0, 0), 1080), size(2, 2));
        assert_eq!(target_size(size(1, 1), 1080), size(2, 2));
        assert_eq!(target_size(size(1, 3000), 1080), size(2, 1080));
    }
}
