//! A cursor's shape as two small pictures the GPU can draw it from, made once
//! each time the shape changes.
//!
//! Windows keeps a cursor as two masks, as `DrawIconEx` reads them: an AND mask
//! that says which pixels are left alone, and a colour (or, for a black and
//! white cursor, an XOR mask) that is then put over or XORed into the screen.
//! Blending on the GPU cannot XOR, so the pixels that invert what is under them
//! (the text cursor's, a black and white cursor's) go in a picture of their own,
//! drawn white with a blend that turns what is under it inside out, as
//! Sunshine's `display_vram.cpp` draws them. Everything else is an ordinary
//! picture with straight alpha.
//!
//! Drawing it this way replaced GDI drawing into the shared picture, which
//! waited for the GPU each time: on Windows 10 beside an uncapped game that took
//! 33–47 ms a picture and held a whole-screen share to 21 fps (Nov 19 2026).

/// What goes over the AND mask: a colour picture, or a black and white
/// cursor's XOR mask.
pub(crate) enum Xor<'a> {
    /// 32-bit BGRA rows, top first, `width * 4` bytes each.
    Color(&'a [u8]),
    /// 1-bit rows, top first, padded as the AND mask's are.
    Mono(&'a [u8]),
}

/// A cursor shape, in 32-bit BGRA pictures of `width` by `height`, top row first.
#[derive(Debug, PartialEq)]
pub(crate) struct ShapeImages {
    pub(crate) width: u32,
    pub(crate) height: u32,
    /// Put over the screen with straight alpha.
    pub(crate) blended: Vec<u8>,
    /// White where the screen is turned inside out, black elsewhere; `None`
    /// when no pixel inverts.
    pub(crate) inverted: Option<Vec<u8>>,
}

/// The bytes in a row of a 1-bit picture `width` wide: DIB rows are padded to
/// four bytes.
pub(crate) fn mono_stride(width: u32) -> usize {
    (width as usize).div_ceil(32) * 4
}

/// Whether bit `x` of a 1-bit row is set; the leftmost pixel is the top bit.
fn bit(row: &[u8], x: usize) -> bool {
    row[x / 8] & (0x80 >> (x % 8)) != 0
}

const CLEAR: [u8; 4] = [0, 0, 0, 0];
const WHITE: [u8; 4] = [255, 255, 255, 255];
const BLACK: [u8; 4] = [0, 0, 0, 255];

/// The two pictures for a cursor `width` by `height`, from its AND mask rows and
/// what goes over them. `None` if the masks are shorter than the size says.
///
/// As `DrawIconEx` does, a colour cursor with any alpha is drawn by its alpha
/// alone. One without alpha is opaque where the AND mask is clear, and where it
/// is set XORs its colour in: black there leaves the screen alone, and any other
/// colour is taken as inverting, the only XOR blending can do (white, in the
/// cursors Windows ships).
pub(crate) fn shape_images(
    width: u32,
    height: u32,
    and: &[u8],
    xor: Xor<'_>,
) -> Option<ShapeImages> {
    let (w, h) = (width as usize, height as usize);
    let stride = mono_stride(width);
    if and.len() < stride * h {
        return None;
    }
    match xor {
        Xor::Color(color) if color.len() < w * h * 4 => return None,
        Xor::Mono(mono) if mono.len() < stride * h => return None,
        _ => {}
    }
    let has_alpha =
        matches!(xor, Xor::Color(color) if color[..w * h * 4].chunks_exact(4).any(|p| p[3] != 0));
    let mut blended = Vec::with_capacity(w * h * 4);
    let mut inverted = vec![0u8; w * h * 4];
    let mut inverts = false;
    for y in 0..h {
        let and_row = &and[y * stride..][..stride];
        for x in 0..w {
            let keep = bit(and_row, x);
            let (over, invert) = match xor {
                Xor::Color(color) => {
                    let pixel: [u8; 4] = color[(y * w + x) * 4..][..4].try_into().unwrap();
                    if has_alpha {
                        (pixel, false)
                    } else if !keep {
                        ([pixel[0], pixel[1], pixel[2], 255], false)
                    } else {
                        (CLEAR, pixel[..3] != [0, 0, 0])
                    }
                }
                Xor::Mono(mono) => match (keep, bit(&mono[y * stride..][..stride], x)) {
                    (false, false) => (BLACK, false),
                    (false, true) => (WHITE, false),
                    (true, false) => (CLEAR, false),
                    (true, true) => (CLEAR, true),
                },
            };
            blended.extend_from_slice(&over);
            if invert {
                inverted[(y * w + x) * 4..][..4].copy_from_slice(&WHITE);
                inverts = true;
            }
        }
    }
    Some(ShapeImages {
        width,
        height,
        blended,
        inverted: inverts.then_some(inverted),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 2x2 cursor's 1-bit rows from its pixels, each padded to four bytes.
    fn rows(bits: [[bool; 2]; 2]) -> Vec<u8> {
        bits.iter()
            .flat_map(|row| {
                let byte = (row[0] as u8) << 7 | (row[1] as u8) << 6;
                [byte, 0, 0, 0]
            })
            .collect()
    }

    fn pixel(picture: &[u8], at: usize) -> [u8; 4] {
        picture[at * 4..][..4].try_into().unwrap()
    }

    #[test]
    fn a_black_and_white_cursor_keeps_all_four_kinds_of_pixel() {
        // AND, XOR: black, white, left alone, inverted.
        let and = rows([[false, false], [true, true]]);
        let xor = rows([[false, true], [false, true]]);
        let shape = shape_images(2, 2, &and, Xor::Mono(&xor)).unwrap();
        assert_eq!(pixel(&shape.blended, 0), BLACK);
        assert_eq!(pixel(&shape.blended, 1), WHITE);
        assert_eq!(pixel(&shape.blended, 2), CLEAR);
        assert_eq!(pixel(&shape.blended, 3), CLEAR);
        let inverted = shape.inverted.unwrap();
        assert_eq!(pixel(&inverted, 2), CLEAR);
        assert_eq!(pixel(&inverted, 3), WHITE);
        assert_eq!(pixel(&inverted, 0), CLEAR);
    }

    #[test]
    fn a_cursor_with_alpha_is_drawn_by_its_alpha_alone() {
        let and = rows([[true, true], [true, true]]);
        let color = [10, 20, 30, 128, 0, 0, 0, 0, 1, 2, 3, 255, 255, 255, 255, 0];
        let shape = shape_images(2, 2, &and, Xor::Color(&color)).unwrap();
        assert_eq!(shape.blended, color.to_vec());
        assert_eq!(shape.inverted, None);
    }

    #[test]
    fn a_colour_cursor_without_alpha_is_opaque_inside_its_mask() {
        let and = rows([[false, true], [true, false]]);
        let color = [10, 20, 30, 0, 0, 0, 0, 0, 255, 255, 255, 0, 40, 50, 60, 0];
        let shape = shape_images(2, 2, &and, Xor::Color(&color)).unwrap();
        assert_eq!(pixel(&shape.blended, 0), [10, 20, 30, 255]);
        assert_eq!(
            pixel(&shape.blended, 1),
            CLEAR,
            "black over a set mask leaves the screen"
        );
        assert_eq!(pixel(&shape.blended, 2), CLEAR);
        assert_eq!(pixel(&shape.blended, 3), [40, 50, 60, 255]);
        let inverted = shape.inverted.unwrap();
        assert_eq!(pixel(&inverted, 1), CLEAR);
        assert_eq!(pixel(&inverted, 2), WHITE, "white over a set mask inverts");
    }

    #[test]
    fn rows_are_read_past_their_padding() {
        // 33 wide: two four-byte words a row, the last pixel in the second.
        let stride = mono_stride(33);
        assert_eq!(stride, 8);
        let and = vec![0u8; stride];
        let mut xor = vec![0u8; stride];
        xor[4] = 0x80;
        let shape = shape_images(33, 1, &and, Xor::Mono(&xor)).unwrap();
        assert_eq!(pixel(&shape.blended, 32), WHITE);
        assert_eq!(pixel(&shape.blended, 31), BLACK);
    }

    #[test]
    fn masks_shorter_than_the_size_are_refused() {
        let and = rows([[false, false], [false, false]]);
        assert_eq!(shape_images(2, 3, &and, Xor::Mono(&and)), None);
        assert_eq!(shape_images(2, 2, &and, Xor::Color(&[0; 15])), None);
    }
}
