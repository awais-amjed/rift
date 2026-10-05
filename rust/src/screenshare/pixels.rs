//! Pure pixel work, kept free of the platform so it can be tested anywhere:
//! the Windows thumbnail, and a resized window's letterbox.

/// Shrink a strided BGRA frame to a packed RGB image at most `max_width`
/// wide, by nearest-neighbour sampling straight from the source. Sampling
/// while converting means a 4K frame costs a few hundred pixel reads rather
/// than a full-frame copy followed by a resize.
///
/// Returns the packed pixels and the output size. `None` when the frame is
/// empty or shorter than its own dimensions claim.
// Only the Windows thumbnail path calls it; the tests run everywhere.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub(crate) fn thumbnail_rgb(
    bgra: &[u8],
    width: u32,
    height: u32,
    stride: u32,
    max_width: u32,
) -> Option<(Vec<u8>, u32, u32)> {
    if width == 0 || height == 0 || max_width == 0 || stride < width * 4 {
        return None;
    }
    if bgra.len() < (stride * (height - 1) + width * 4) as usize {
        return None;
    }
    let out_w = max_width.min(width);
    let out_h = ((out_w as f64 * height as f64 / width as f64).round() as u32).max(1);

    let mut rgb = Vec::with_capacity((out_w * out_h * 3) as usize);
    for oy in 0..out_h {
        let sy = (oy as u64 * height as u64 / out_h as u64) as usize;
        let row = sy * stride as usize;
        for ox in 0..out_w {
            let sx = (ox as u64 * width as u64 / out_w as u64) as usize;
            let p = row + sx * 4;
            rgb.extend_from_slice(&[bgra[p + 2], bgra[p + 1], bgra[p]]);
        }
    }
    Some((rgb, out_w, out_h))
}

/// Copy one plane of `width` x `height` samples into `dst` with its top-left
/// at (`x`, `y`). Both planes are strided; the caller keeps the copy inside
/// `dst`, which a [`letterbox`](super::resolution::letterbox) rectangle is.
// Only a desktop share calls it; the tests run everywhere.
#[cfg_attr(not(desktop), allow(dead_code))]
pub(crate) fn copy_plane(
    src: &[u8],
    src_stride: usize,
    dst: &mut [u8],
    dst_stride: usize,
    (x, y): (usize, usize),
    (width, height): (usize, usize),
) {
    for row in 0..height {
        let from = row * src_stride;
        let to = (y + row) * dst_stride + x;
        dst[to..to + width].copy_from_slice(&src[from..from + width]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A frame whose every pixel encodes its own coordinates: B = x, G = y.
    fn frame(width: u32, height: u32, stride: u32) -> Vec<u8> {
        let mut data = vec![0u8; (stride * height) as usize];
        for y in 0..height {
            for x in 0..width {
                let p = (y * stride + x * 4) as usize;
                data[p] = x as u8;
                data[p + 1] = y as u8;
                data[p + 2] = 200;
                data[p + 3] = 255;
            }
        }
        data
    }

    #[test]
    fn small_frames_are_not_enlarged() {
        let (rgb, w, h) = thumbnail_rgb(&frame(8, 4, 32), 8, 4, 32, 320).unwrap();
        assert_eq!((w, h), (8, 4));
        assert_eq!(rgb.len(), 8 * 4 * 3);
    }

    #[test]
    fn channels_are_reordered_to_rgb() {
        let (rgb, _, _) = thumbnail_rgb(&frame(2, 1, 8), 2, 1, 8, 320).unwrap();
        assert_eq!(&rgb[..3], &[200, 0, 0]);
        assert_eq!(&rgb[3..6], &[200, 0, 1]);
    }

    #[test]
    fn scaling_keeps_aspect_and_samples_the_right_pixels() {
        let (rgb, w, h) = thumbnail_rgb(&frame(200, 100, 800), 200, 100, 800, 20).unwrap();
        assert_eq!((w, h), (20, 10));
        // Last output pixel comes from source (190, 90).
        let last = &rgb[rgb.len() - 3..];
        assert_eq!(last, &[200, 90, 190]);
    }

    #[test]
    fn padded_strides_are_respected() {
        let (a, ..) = thumbnail_rgb(&frame(3, 3, 12), 3, 3, 12, 320).unwrap();
        let (b, ..) = thumbnail_rgb(&frame(3, 3, 64), 3, 3, 64, 320).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn short_or_empty_data_is_refused() {
        assert!(thumbnail_rgb(&[], 0, 0, 0, 320).is_none());
        assert!(thumbnail_rgb(&[0; 8], 4, 4, 16, 320).is_none());
    }

    #[test]
    fn a_plane_lands_at_its_offset_and_nothing_else_moves() {
        // A 2x2 plane with a padded stride of 3, into a 5-wide, 4-high one.
        let src = [1, 2, 9, 3, 4, 9];
        let mut dst = vec![0u8; 5 * 4];
        copy_plane(&src, 3, &mut dst, 5, (2, 1), (2, 2));
        #[rustfmt::skip]
        assert_eq!(dst, [
            0, 0, 0, 0, 0,
            0, 0, 1, 2, 0,
            0, 0, 3, 4, 0,
            0, 0, 0, 0, 0,
        ]);
    }
}
