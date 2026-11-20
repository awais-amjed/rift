//! A cursor's shape as two small pictures the GPU can draw it from, made once
//! each time the shape changes.
//!
//! Windows keeps a cursor as two masks, as `DrawIconEx` reads them: an AND mask
//! that says which pixels are left alone, and a colour (or, for a black and
//! white cursor, an XOR mask) that is then put over or XORed into the screen.
//! DXGI's desktop duplication hands a shape over in one of three kinds
//! ([`dxgi_shape_images`]), the same masks laid out its own way.
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

/// The largest side a shape is taken with. Windows' largest pointer size is 256.
const LARGEST: u32 = 512;

/// `DXGI_OUTDUPL_POINTER_SHAPE_TYPE`: the AND mask over the XOR one, each a
/// 1-bit picture, so twice as tall as the cursor.
pub(crate) const DXGI_MONOCHROME: u32 = 1;
/// BGRA with straight alpha.
pub(crate) const DXGI_COLOR: u32 = 2;
/// BGRA whose alpha says what the colour does: 0 put over the screen, 0xFF
/// XORed into it.
pub(crate) const DXGI_MASKED_COLOR: u32 = 4;

/// The two pictures for a shape DXGI's duplication handed over
/// (`GetFramePointerShape`): its kind, its `width` and `height` as DXGI gives
/// them, and `pitch` bytes a row. `None` for a kind not known, a size out of
/// reach, or bytes shorter than the size says.
pub(crate) fn dxgi_shape_images(
    kind: u32,
    width: u32,
    height: u32,
    pitch: usize,
    bytes: &[u8],
) -> Option<ShapeImages> {
    if width == 0 || height == 0 || width > LARGEST || height > LARGEST * 2 {
        return None;
    }
    let (w, h) = (width as usize, height as usize);
    let row_bytes = match kind {
        DXGI_MONOCHROME => w.div_ceil(8),
        _ => w * 4,
    };
    if pitch < row_bytes || bytes.len() < pitch * (h - 1) + row_bytes {
        return None;
    }
    let row = |y: usize| &bytes[y * pitch..][..row_bytes];
    match kind {
        DXGI_MONOCHROME => {
            let h = h / 2;
            if h == 0 {
                return None;
            }
            // DXGI's rows are as long as they need be; a DIB's are padded.
            let stride = mono_stride(width);
            let padded = |rows: std::ops::Range<usize>| {
                let mut out = Vec::with_capacity(stride * rows.len());
                for y in rows {
                    out.extend_from_slice(row(y));
                    out.resize(out.len() + stride - row_bytes, 0);
                }
                out
            };
            shape_images(width, h as u32, &padded(0..h), Xor::Mono(&padded(h..2 * h)))
        }
        DXGI_COLOR => {
            if h > LARGEST as usize {
                return None;
            }
            Some(ShapeImages {
                width,
                height,
                blended: (0..h).flat_map(row).copied().collect(),
                inverted: None,
            })
        }
        DXGI_MASKED_COLOR => {
            if h > LARGEST as usize {
                return None;
            }
            // As a colour cursor without alpha: the AND mask set where the
            // colour is XORed in, and the colour's alpha cleared.
            let stride = mono_stride(width);
            let mut and = vec![0u8; stride * h];
            let mut color = Vec::with_capacity(w * h * 4);
            for y in 0..h {
                for (x, pixel) in row(y).as_chunks::<4>().0.iter().enumerate() {
                    if pixel[3] == 0xFF {
                        and[y * stride + x / 8] |= 0x80 >> (x % 8);
                    }
                    color.extend_from_slice(&[pixel[0], pixel[1], pixel[2], 0]);
                }
            }
            shape_images(width, height, &and, Xor::Color(&color))
        }
        _ => None,
    }
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
    fn a_dxgi_black_and_white_shape_is_read_by_its_pitch() {
        // 2x2, one byte a row: AND rows then XOR rows, as in the GDI test above.
        let bytes = [0b0000_0000, 0b1100_0000, 0b0100_0000, 0b0100_0000];
        let shape = dxgi_shape_images(DXGI_MONOCHROME, 2, 4, 1, &bytes).unwrap();
        assert_eq!((shape.width, shape.height), (2, 2));
        assert_eq!(pixel(&shape.blended, 0), BLACK);
        assert_eq!(pixel(&shape.blended, 1), WHITE);
        assert_eq!(pixel(&shape.blended, 2), CLEAR);
        assert_eq!(pixel(&shape.inverted.unwrap(), 3), WHITE);
    }

    #[test]
    fn a_dxgi_colour_shape_keeps_its_alpha_and_drops_the_padding() {
        // 1x2 with a pitch of 8: four bytes of padding after each pixel.
        let bytes = [1, 2, 3, 128, 9, 9, 9, 9, 4, 5, 6, 0];
        let shape = dxgi_shape_images(DXGI_COLOR, 1, 2, 8, &bytes).unwrap();
        assert_eq!(shape.blended, vec![1, 2, 3, 128, 4, 5, 6, 0]);
        assert_eq!(shape.inverted, None);
    }

    #[test]
    fn a_dxgi_masked_shape_puts_over_or_inverts_by_its_alpha() {
        // Opaque red, a black XOR (nothing), a white XOR (inverts).
        let bytes = [0, 0, 255, 0, 0, 0, 0, 0xFF, 255, 255, 255, 0xFF];
        let shape = dxgi_shape_images(DXGI_MASKED_COLOR, 3, 1, 12, &bytes).unwrap();
        assert_eq!(pixel(&shape.blended, 0), [0, 0, 255, 255]);
        assert_eq!(pixel(&shape.blended, 1), CLEAR);
        assert_eq!(pixel(&shape.blended, 2), CLEAR);
        let inverted = shape.inverted.unwrap();
        assert_eq!(pixel(&inverted, 1), CLEAR);
        assert_eq!(pixel(&inverted, 2), WHITE);
    }

    #[test]
    fn a_dxgi_shape_it_cannot_read_is_refused() {
        assert_eq!(dxgi_shape_images(DXGI_COLOR, 2, 2, 8, &[0; 15]), None);
        assert_eq!(dxgi_shape_images(DXGI_COLOR, 2, 2, 4, &[0; 16]), None);
        assert_eq!(dxgi_shape_images(DXGI_MONOCHROME, 8, 1, 1, &[0; 1]), None);
        assert_eq!(dxgi_shape_images(3, 1, 1, 4, &[0; 4]), None);
        assert_eq!(dxgi_shape_images(DXGI_COLOR, 0, 1, 4, &[0; 4]), None);
    }

    #[test]
    fn masks_shorter_than_the_size_are_refused() {
        let and = rows([[false, false], [false, false]]);
        assert_eq!(shape_images(2, 3, &and, Xor::Mono(&and)), None);
        assert_eq!(shape_images(2, 2, &and, Xor::Color(&[0; 15])), None);
    }
}
