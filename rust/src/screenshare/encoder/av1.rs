//! What an AV1 temporal unit holds, read from its OBUs.
//!
//! LiveKit's pass-through tidies an AV1 frame before WebRTC packetizes it
//! (`third_party/webrtc-sys/src/av1_bitstream.cpp`), but sends each one as a
//! single picture: a frame the encoder held back to show later, or two
//! pictures in one sample, would reach the viewer out of step. So the frame
//! headers are read here, to tell a keyframe and to check what an encoder
//! makes.

/// OBU types this code acts on (AV1 spec, 6.2.2).
const OBU_SEQUENCE_HEADER: u8 = 1;
const OBU_FRAME_HEADER: u8 = 3;
const OBU_FRAME: u8 = 6;

/// `frame_type` KEY_FRAME (AV1 spec, 6.8.2).
const KEY_FRAME: u32 = 0;

/// The OBUs in a low-overhead payload: each one's type and its body, the
/// header and size field left out. Stops at the first one that does not fit.
pub(crate) fn obus(payload: &[u8]) -> Vec<(u8, &[u8])> {
    let mut found = Vec::new();
    let mut at = 0;
    while at < payload.len() {
        let header = payload[at];
        let kind = (header >> 3) & 0x0f;
        let has_extension = header & 0x04 != 0;
        let has_size = header & 0x02 != 0;
        let mut body = at + 1 + usize::from(has_extension);
        let size = if has_size {
            match leb128(&payload[body.min(payload.len())..]) {
                Some((size, read)) => {
                    body += read;
                    size
                }
                None => break,
            }
        } else {
            // Without a size, the OBU runs to the end of the payload.
            payload.len().saturating_sub(body)
        };
        let Some(end) = body.checked_add(size).filter(|&end| end <= payload.len()) else {
            break;
        };
        found.push((kind, &payload[body..end]));
        at = end;
    }
    found
}

/// An unsigned LEB128 value and how many bytes it took.
fn leb128(bytes: &[u8]) -> Option<(usize, usize)> {
    let mut value = 0u64;
    for (i, &byte) in bytes.iter().take(8).enumerate() {
        value |= u64::from(byte & 0x7f) << (7 * i);
        if byte & 0x80 == 0 {
            return usize::try_from(value).ok().map(|v| (v, i + 1));
        }
    }
    None
}

/// What one frame header says about its picture.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FrameHeader {
    pub keyframe: bool,
    /// Shown now, rather than kept to be shown by a later header.
    pub shown: bool,
    /// Shows a frame decoded earlier instead of coding a new one.
    pub existing: bool,
}

/// The frame headers in a temporal unit, in order.
///
/// A sequence header with `reduced_still_picture_header` set means every
/// frame is a shown keyframe with no header bits for either; a real-time
/// encoder never sets it, so a unit without a sequence header is read as if
/// it were clear.
pub(crate) fn frame_headers(payload: &[u8]) -> Vec<FrameHeader> {
    let mut reduced_still_picture = false;
    let mut headers = Vec::new();
    for (kind, body) in obus(payload) {
        match kind {
            OBU_SEQUENCE_HEADER => {
                // seq_profile f(3), still_picture f(1),
                // reduced_still_picture_header f(1).
                let mut bits = Bits::new(body);
                bits.read(4);
                reduced_still_picture = bits.read(1) == Some(1);
            }
            OBU_FRAME_HEADER | OBU_FRAME => {
                if reduced_still_picture {
                    headers.push(FrameHeader {
                        keyframe: true,
                        shown: true,
                        existing: false,
                    });
                    continue;
                }
                let mut bits = Bits::new(body);
                let header = match bits.read(1) {
                    Some(1) => FrameHeader {
                        keyframe: false,
                        shown: true,
                        existing: true,
                    },
                    Some(_) => {
                        let (Some(frame_type), Some(show_frame)) = (bits.read(2), bits.read(1))
                        else {
                            continue;
                        };
                        FrameHeader {
                            keyframe: frame_type == KEY_FRAME,
                            shown: show_frame == 1,
                            existing: false,
                        }
                    }
                    None => continue,
                };
                headers.push(header);
            }
            _ => {}
        }
    }
    headers
}

/// Whether the temporal unit starts with a keyframe a viewer can decode from.
pub(crate) fn is_keyframe(payload: &[u8]) -> bool {
    frame_headers(payload)
        .first()
        .is_some_and(|header| header.keyframe)
}

/// Whether the temporal unit carries a sequence header.
pub(crate) fn has_sequence_header(payload: &[u8]) -> bool {
    obus(payload)
        .iter()
        .any(|&(kind, _)| kind == OBU_SEQUENCE_HEADER)
}

/// Reads bits most significant first, as AV1 headers are written.
struct Bits<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Bits<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, at: 0 }
    }

    fn read(&mut self, count: usize) -> Option<u32> {
        let mut value = 0;
        for _ in 0..count {
            let byte = *self.bytes.get(self.at / 8)?;
            let bit = (byte >> (7 - self.at % 8)) & 1;
            value = (value << 1) | u32::from(bit);
            self.at += 1;
        }
        Some(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An OBU with a size field: header byte, LEB128 size, body.
    fn obu(kind: u8, body: &[u8]) -> Vec<u8> {
        let mut bytes = vec![(kind << 3) | 0x02, body.len() as u8];
        bytes.extend_from_slice(body);
        bytes
    }

    const TEMPORAL_DELIMITER: u8 = 2;

    #[test]
    fn a_keyframe_unit_is_read_as_one() {
        // show_existing_frame 0, frame_type KEY (00), show_frame 1.
        let unit = [
            obu(TEMPORAL_DELIMITER, &[]),
            obu(OBU_SEQUENCE_HEADER, &[0b0000_0000, 0]),
            obu(OBU_FRAME, &[0b0001_0000, 0xaa]),
        ]
        .concat();
        assert_eq!(
            frame_headers(&unit),
            vec![FrameHeader {
                keyframe: true,
                shown: true,
                existing: false
            }]
        );
        assert!(is_keyframe(&unit));
        assert!(has_sequence_header(&unit));
    }

    #[test]
    fn an_inter_frame_is_not_a_keyframe() {
        // show_existing_frame 0, frame_type INTER (01), show_frame 1.
        let unit = obu(OBU_FRAME, &[0b0011_0000]);
        assert!(!is_keyframe(&unit));
        assert!(!has_sequence_header(&unit));
    }

    #[test]
    fn a_hidden_frame_and_a_shown_existing_one_are_told_apart() {
        // A hidden inter frame (show_frame 0), then show_existing_frame 1.
        let unit = [
            obu(OBU_FRAME, &[0b0010_0000]),
            obu(OBU_FRAME_HEADER, &[0b1000_0000]),
        ]
        .concat();
        assert_eq!(
            frame_headers(&unit),
            vec![
                FrameHeader {
                    keyframe: false,
                    shown: false,
                    existing: false
                },
                FrameHeader {
                    keyframe: false,
                    shown: true,
                    existing: true
                },
            ]
        );
    }

    #[test]
    fn a_reduced_still_picture_sequence_makes_every_frame_a_shown_keyframe() {
        // reduced_still_picture_header is the fifth bit of the sequence header.
        let unit = [
            obu(OBU_SEQUENCE_HEADER, &[0b0000_1000]),
            obu(OBU_FRAME, &[0b1111_1111]),
        ]
        .concat();
        assert!(is_keyframe(&unit));
    }

    #[test]
    fn an_obu_without_a_size_runs_to_the_end() {
        let unit = [
            &obu(TEMPORAL_DELIMITER, &[])[..],
            &[OBU_FRAME << 3, 0b0001_0000, 1, 2],
        ]
        .concat();
        let found = obus(&unit);
        assert_eq!(found.len(), 2);
        assert_eq!(found[1], (OBU_FRAME, &[0b0001_0000, 1, 2][..]));
    }

    #[test]
    fn a_size_past_the_end_stops_the_reading() {
        let mut unit = obu(OBU_FRAME, &[0b0001_0000]);
        unit[1] = 9;
        assert!(obus(&unit).is_empty());
        assert!(!is_keyframe(&unit));
    }

    #[test]
    fn a_long_size_is_read_across_bytes() {
        assert_eq!(leb128(&[0x80, 0x01]), Some((128, 2)));
        assert_eq!(leb128(&[0x80]), None);
    }
}
