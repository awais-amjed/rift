//! What an H264 access unit holds, read from its Annex B bytes.
//!
//! WebRTC's H264 packetizer splits a payload at its start codes, and a viewer
//! can only start decoding at an IDR that carries the parameter sets. A
//! hardware encoder may emit those once, at the start, so they are kept here
//! and put back in front of any IDR that comes without them.

/// NAL unit types this code acts on (H.264 table 7-1).
const NAL_IDR: u8 = 5;
const NAL_SPS: u8 = 7;
const NAL_PPS: u8 = 8;

/// The NAL units in an Annex B payload: each one's type and its bytes, start
/// code included, so a unit can be copied out and put in front of another.
pub(crate) fn nal_units(payload: &[u8]) -> Vec<(u8, &[u8])> {
    let starts = start_codes(payload);
    starts
        .iter()
        .enumerate()
        .filter_map(|(i, &(at, len))| {
            let end = starts.get(i + 1).map_or(payload.len(), |&(next, _)| next);
            let header = *payload.get(at + len)?;
            Some((header & 0x1f, &payload[at..end]))
        })
        .collect()
}

/// Where each start code begins, and whether it is the 3 or 4 byte form.
fn start_codes(payload: &[u8]) -> Vec<(usize, usize)> {
    let mut found = Vec::new();
    let mut i = 0;
    while i + 3 <= payload.len() {
        if payload[i] == 0 && payload[i + 1] == 0 && payload[i + 2] == 1 {
            if i > 0 && payload[i - 1] == 0 {
                found.push((i - 1, 4));
            } else {
                found.push((i, 3));
            }
            i += 3;
        } else {
            i += 1;
        }
    }
    found
}

/// Whether the access unit starts a picture a viewer can decode from.
pub(crate) fn is_idr(payload: &[u8]) -> bool {
    nal_units(payload).iter().any(|&(kind, _)| kind == NAL_IDR)
}

/// The access unit with every start code in the four-byte form, or `None`
/// when it already is.
///
/// LiveKit's frame encryption leaves the bytes up to the first slice readable
/// and authenticates them. A receiver rebuilds a frame from its RTP packets
/// with four-byte start codes throughout, so an encoder that wrote a
/// three-byte one there (Intel's does, before every slice) has its frames
/// authenticated against bytes the receiver never sees: every frame fails
/// to decrypt and no viewer gets a picture (found Oct 4 2026).
pub(crate) fn with_long_start_codes(payload: &[u8]) -> Option<Vec<u8>> {
    let codes = start_codes(payload);
    if codes.iter().all(|&(_, len)| len == 4) {
        return None;
    }
    let mut whole = Vec::with_capacity(payload.len() + codes.len());
    for (_, unit) in nal_units(payload) {
        whole.extend_from_slice(&[0, 0, 0, 1]);
        whole.extend_from_slice(&unit[start_code_len(unit)..]);
    }
    Some(whole)
}

/// The access unit as LiveKit is to be handed it, or `None` when that is
/// the encoder's own bytes: an IDR's PPS id brought within what encryption
/// leaves readable ([`with_readable_pps_id`]), then every start code in the
/// four-byte form ([`with_long_start_codes`]).
pub(crate) fn for_encryption(payload: &[u8]) -> Option<Vec<u8>> {
    let readable = with_readable_pps_id(payload);
    with_long_start_codes(readable.as_deref().unwrap_or(payload)).or(readable)
}

/// Whether a viewer can still find this access unit's parameter sets once
/// LiveKit has encrypted it. Always true of anything but an IDR.
///
/// The frame cryptor leaves only the first slice's NAL header and the byte
/// after it readable, and a receiver reads the IDR's `pic_parameter_set_id`
/// from there to find its PPS. An id that runs past that byte is read from
/// ciphertext, so about one keyframe in two names a PPS that does not exist;
/// the receiver drops it and every picture after it, and asks for another.
/// FFmpeg's VAAPI encoder wrote slice type 7 (I, every slice alike), whose
/// seven bits pushed the id one bit too far: whoever was watching froze for a
/// moment each time somebody joined (found Oct 16 2026). Types 2 and 0, as
/// NVENC writes them, leave it room.
pub(crate) fn idr_readable_when_encrypted(payload: &[u8]) -> bool {
    let Some((_, unit)) = nal_units(payload)
        .into_iter()
        .find(|&(kind, _)| kind == NAL_IDR)
    else {
        return true;
    };
    // first_mb_in_slice, slice_type, pic_parameter_set_id: each ue(v), read
    // from the bytes after the NAL header. Emulation prevention bytes cannot
    // occur in the first two, which is all this is asked about.
    let mut bits = Bits::new(&unit[start_code_len(unit) + 1..]);
    for _ in 0..3 {
        if bits.exp_golomb().is_none() {
            // Too short to tell; nothing to warn about.
            return true;
        }
    }
    bits.at <= 8
}

/// The access unit with its IDR slices' headers rewritten so the PPS id
/// falls within what encryption leaves readable, or `None` when it already
/// does or the header cannot be rewritten.
///
/// Intel's encoders on Windows, Quick Sync through FFmpeg and Media
/// Foundation's alike, write every IDR as slice type 7, and the slice header
/// is written by Intel's runtime in the driver, which has no setting for it
/// (Oct 16 2026, an RTX 3070 Ti laptop's Iris Xe; FFmpeg's `low_power`,
/// profile, slice count and `repeat_pps` all left it at 7). So the header is
/// rewritten here: the slice type as the same type without "every slice
/// alike" (7 to 2, 5 to 0), and the IDR's `idr_pic_id`, a few fields further
/// on, made as many bits longer as the type got shorter. The header keeps its
/// length, so the slice data after it stays where it was, bit for bit, which
/// CABAC's and PCM macroblocks' byte alignment needs. Every IDR slice of the
/// picture gets the same new id, and distinct ids stay distinct, as
/// consecutive IDRs' must.
pub(crate) fn with_readable_pps_id(payload: &[u8]) -> Option<Vec<u8>> {
    if idr_readable_when_encrypted(payload) {
        return None;
    }
    let units = nal_units(payload);
    let mut whole = Vec::with_capacity(payload.len() + 8);
    for &(kind, unit) in &units {
        let code = start_code_len(unit);
        whole.extend_from_slice(&unit[..code]);
        if kind == NAL_IDR {
            whole.extend_from_slice(&shorter_slice_type(&unit[code..], &units)?);
        } else {
            whole.extend_from_slice(&unit[code..]);
        }
    }
    Some(whole)
}

/// One IDR slice NAL unit (header byte first, no start code) with the slice
/// type shortened and `idr_pic_id` lengthened to match; see
/// [`with_readable_pps_id`].
fn shorter_slice_type(nal: &[u8], units: &[(u8, &[u8])]) -> Option<Vec<u8>> {
    let (&header, ebsp) = nal.split_first()?;
    let mut rbsp = unescape(ebsp);
    let mut bits = Bits::new(&rbsp);
    let first_mb = bits.exp_golomb()?;
    let slice_type = bits.exp_golomb()?;
    if !(5..=9).contains(&slice_type) {
        return None;
    }
    let pps_id = bits.exp_golomb()?;
    let between = bits.at;
    let numbering = frame_numbering(units, pps_id)?;
    if numbering.separate_colour_planes {
        bits.read(2)?;
    }
    bits.read(numbering.frame_num_bits)?;
    if !numbering.frames_only && bits.read(1)? == 1 {
        bits.read(1)?;
    }
    let id_at = bits.at;
    let idr_pic_id = bits.exp_golomb()?;
    let end = bits.at;
    let short_type = slice_type - 5;
    let saved = exp_golomb_len(slice_type) - exp_golomb_len(short_type);
    let longer_id = longer_by(idr_pic_id, saved)?;

    let mut prefix = Vec::with_capacity(end);
    push_exp_golomb(&mut prefix, first_mb);
    push_exp_golomb(&mut prefix, short_type);
    push_exp_golomb(&mut prefix, pps_id);
    let mut copy = Bits::new(&rbsp);
    copy.at = between;
    while copy.at < id_at {
        prefix.push(copy.bit()?);
    }
    push_exp_golomb(&mut prefix, longer_id);
    debug_assert_eq!(prefix.len(), end);
    for (at, &bit) in prefix.iter().enumerate() {
        let mask = 0x80 >> (at % 8);
        if bit {
            rbsp[at / 8] |= mask;
        } else {
            rbsp[at / 8] &= !mask;
        }
    }
    let mut out = vec![header];
    out.extend_from_slice(&escape(&rbsp));
    Some(out)
}

/// What an IDR slice header holds between its PPS id and its `idr_pic_id`,
/// as the SPS it names says.
struct FrameNumbering {
    separate_colour_planes: bool,
    frame_num_bits: u32,
    frames_only: bool,
}

/// [`FrameNumbering`] from the SPS that the PPS numbered `pps_id` names,
/// both from the same access unit, where every encoder here puts them in
/// front of an IDR ([`ParameterSets`]).
fn frame_numbering(units: &[(u8, &[u8])], pps_id: u32) -> Option<FrameNumbering> {
    let body = |unit: &[u8]| unescape(&unit[(start_code_len(unit) + 1).min(unit.len())..]);
    let sps_id = units
        .iter()
        .filter(|&&(kind, _)| kind == NAL_PPS)
        .find_map(|&(_, unit)| {
            let pps = body(unit);
            let mut bits = Bits::new(&pps);
            (bits.exp_golomb()? == pps_id).then(|| bits.exp_golomb())?
        })?;
    units
        .iter()
        .filter(|&&(kind, _)| kind == NAL_SPS)
        .find_map(|&(_, unit)| sps_numbering(&body(unit), sps_id))
}

/// The fields of an SPS (its RBSP after the NAL header) that a slice header
/// depends on up to `idr_pic_id`, if its id is `sps_id`.
fn sps_numbering(sps: &[u8], sps_id: u32) -> Option<FrameNumbering> {
    let mut bits = Bits::new(sps);
    let profile = bits.read(8)?;
    bits.read(16)?; // constraint flags, level
    if bits.exp_golomb()? != sps_id {
        return None;
    }
    let mut separate_colour_planes = false;
    if matches!(
        profile,
        100 | 110 | 122 | 244 | 44 | 83 | 86 | 118 | 128 | 138 | 139 | 134 | 135
    ) {
        if bits.exp_golomb()? == 3 {
            separate_colour_planes = bits.read(1)? == 1;
        }
        bits.exp_golomb()?; // bit_depth_luma_minus8
        bits.exp_golomb()?; // bit_depth_chroma_minus8
        bits.read(1)?; // qpprime_y_zero_transform_bypass_flag
        if bits.read(1)? == 1 {
            // Scaling matrices, which no encoder here writes: not read.
            return None;
        }
    }
    let frame_num_bits = bits.exp_golomb()? + 4;
    match bits.exp_golomb()? {
        0 => {
            bits.exp_golomb()?; // log2_max_pic_order_cnt_lsb_minus4
        }
        1 => {
            bits.read(1)?; // delta_pic_order_always_zero_flag
            bits.exp_golomb()?; // offset_for_non_ref_pic
            bits.exp_golomb()?; // offset_for_top_to_bottom_field
            for _ in 0..bits.exp_golomb()? {
                bits.exp_golomb()?;
            }
        }
        _ => {}
    }
    bits.exp_golomb()?; // max_num_ref_frames
    bits.read(1)?; // gaps_in_frame_num_value_allowed_flag
    bits.exp_golomb()?; // pic_width_in_mbs_minus1
    bits.exp_golomb()?; // pic_height_in_map_units_minus1
    let frames_only = bits.read(1)? == 1;
    Some(FrameNumbering {
        separate_colour_planes,
        frame_num_bits,
        frames_only,
    })
}

/// Bits in `value` written as ue(v).
fn exp_golomb_len(value: u32) -> u32 {
    2 * (value + 1).ilog2() + 1
}

/// Another `idr_pic_id` whose ue(v) is `extra` bits longer: the same offset
/// within the longer codes, so distinct ids stay distinct. `None` past the
/// largest id H264 allows.
fn longer_by(id: u32, extra: u32) -> Option<u32> {
    if id > 65_535 {
        return None;
    }
    let size = (id + 1).ilog2();
    let longer = (1u32 << (size + extra / 2)) - 1 + (id - ((1 << size) - 1));
    (longer <= 65_535).then_some(longer)
}

fn push_exp_golomb(bits: &mut Vec<bool>, value: u32) {
    let code = value + 1;
    let size = code.ilog2();
    bits.extend(std::iter::repeat_n(false, size as usize));
    bits.extend((0..=size).rev().map(|at| code >> at & 1 == 1));
}

/// A NAL unit's payload without its emulation prevention bytes: the 3 the
/// encoder put after every two zero bytes so no start code appears inside.
fn unescape(ebsp: &[u8]) -> Vec<u8> {
    let mut rbsp = Vec::with_capacity(ebsp.len());
    let mut zeros = 0;
    for &byte in ebsp {
        if zeros >= 2 && byte == 3 {
            zeros = 0;
            continue;
        }
        zeros = if byte == 0 { zeros + 1 } else { 0 };
        rbsp.push(byte);
    }
    rbsp
}

/// [`unescape`] undone.
fn escape(rbsp: &[u8]) -> Vec<u8> {
    let mut ebsp = Vec::with_capacity(rbsp.len() + rbsp.len() / 256 + 1);
    let mut zeros = 0;
    for &byte in rbsp {
        if zeros >= 2 && byte <= 3 {
            ebsp.push(3);
            zeros = 0;
        }
        zeros = if byte == 0 { zeros + 1 } else { 0 };
        ebsp.push(byte);
    }
    if ebsp.last() == Some(&0) {
        ebsp.push(3);
    }
    ebsp
}

fn start_code_len(unit: &[u8]) -> usize {
    if unit.starts_with(&[0, 0, 0, 1]) {
        4
    } else {
        3
    }
}

/// A reader of the bits of a NAL unit's payload.
struct Bits<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Bits<'a> {
    fn new(bytes: &'a [u8]) -> Bits<'a> {
        Bits { bytes, at: 0 }
    }

    fn bit(&mut self) -> Option<bool> {
        let byte = self.bytes.get(self.at / 8)?;
        let bit = byte >> (7 - self.at % 8) & 1 == 1;
        self.at += 1;
        Some(bit)
    }

    /// `count` bits, at most 32, as a number.
    fn read(&mut self, count: u32) -> Option<u32> {
        let mut value = 0u32;
        for _ in 0..count {
            value = value << 1 | u32::from(self.bit()?);
        }
        Some(value)
    }

    /// One ue(v): as many zeros, a one, then as many bits again. An se(v) is
    /// stepped over the same way.
    fn exp_golomb(&mut self) -> Option<u32> {
        let mut zeros = 0;
        while !self.bit()? {
            zeros += 1;
            if zeros > 31 {
                return None;
            }
        }
        Some((1u32 << zeros) - 1 + self.read(zeros)?)
    }
}

/// The last SPS and PPS the encoder emitted.
#[derive(Default)]
pub(crate) struct ParameterSets {
    sps: Vec<u8>,
    pps: Vec<u8>,
}

impl ParameterSets {
    /// Note the parameter sets in `payload`, and return it ready to send: an
    /// IDR without them gets the last ones seen in front. Anything else is
    /// handed back as it is.
    pub(crate) fn complete(&mut self, payload: Vec<u8>) -> Vec<u8> {
        let units = nal_units(&payload);
        let (mut has_sps, mut has_pps, mut idr) = (false, false, false);
        for &(kind, bytes) in &units {
            match kind {
                NAL_SPS => {
                    has_sps = true;
                    self.sps = bytes.to_vec();
                }
                NAL_PPS => {
                    has_pps = true;
                    self.pps = bytes.to_vec();
                }
                NAL_IDR => idr = true,
                _ => {}
            }
        }
        if !idr || (has_sps && has_pps) || self.sps.is_empty() || self.pps.is_empty() {
            return payload;
        }
        let mut whole = Vec::with_capacity(self.sps.len() + self.pps.len() + payload.len());
        if !has_sps {
            whole.extend_from_slice(&self.sps);
        }
        if !has_pps {
            whole.extend_from_slice(&self.pps);
        }
        whole.extend_from_slice(&payload);
        whole
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SPS: &[u8] = &[0, 0, 0, 1, 0x67, 0x42, 0xc0, 0x1f];
    const PPS: &[u8] = &[0, 0, 0, 1, 0x68, 0xce, 0x3c, 0x80];
    const IDR: &[u8] = &[0, 0, 1, 0x65, 0x88, 0x84, 0x00];
    const DELTA: &[u8] = &[0, 0, 0, 1, 0x41, 0x9a, 0x02];

    fn join(parts: &[&[u8]]) -> Vec<u8> {
        parts.concat()
    }

    #[test]
    fn an_idr_with_short_slice_types_stays_readable_encrypted() {
        // first_mb 0 (1), slice_type 2 (011), pps_id 0 (1): five bits.
        let idr = [0, 0, 0, 1, 0x65, 0b1011_1000, 0x40];
        assert!(idr_readable_when_encrypted(&join(&[SPS, PPS, &idr])));
    }

    #[test]
    fn an_idr_of_slice_type_7_is_not() {
        // first_mb 0 (1), slice_type 7 (0001000), pps_id 0 (1): nine bits, as
        // FFmpeg's VAAPI encoder wrote them before the patch.
        let idr = [0, 0, 0, 1, 0x65, 0b1000_1000, 0b1000_0000];
        assert!(!idr_readable_when_encrypted(&join(&[SPS, PPS, &idr])));
    }

    /// The start of an access unit from Quick Sync through FFmpeg on an Iris
    /// Xe (Oct 16 2026): its SPS and PPS, and the first bytes of its IDR,
    /// slice type 7, `frame_num` 8 bits, `idr_pic_id` 0.
    const QSV_SPS: &[u8] = &[
        0, 0, 0, 1, 0x27, 0x42, 0x00, 0x2a, 0x95, 0xb0, 0x1e, 0x00, 0x89, 0xf9, 0x70, 0x14, 0x20,
        0xc0, 0xc0, 0xc8, 0x00, 0x00, 0x03, 0x00, 0x08, 0x00, 0x00, 0x03, 0x03, 0xc4, 0xed, 0x0e,
        0x19, 0x70,
    ];
    const QSV_PPS: &[u8] = &[0, 0, 0, 1, 0x28, 0xce, 0x3c, 0x80];
    const QSV_IDR: &[u8] = &[
        0, 0, 1, 0x25, 0x88, 0x80, 0x4f, 0xff, 0xff, 0xd3, 0x14, 0x00, 0x04, 0x0e, 0x6a,
    ];

    /// first_mb_in_slice, slice_type, pic_parameter_set_id and
    /// `idr_pic_id` of the first IDR slice, for a header with 8 bits of
    /// `frame_num`.
    fn idr_fields(payload: &[u8]) -> [u32; 4] {
        let (_, unit) = nal_units(payload)
            .into_iter()
            .find(|&(kind, _)| kind == NAL_IDR)
            .unwrap();
        let rbsp = unescape(&unit[start_code_len(unit) + 1..]);
        let mut bits = Bits::new(&rbsp);
        let first = [0; 3].map(|_| bits.exp_golomb().unwrap());
        bits.read(8).unwrap();
        [first[0], first[1], first[2], bits.exp_golomb().unwrap()]
    }

    #[test]
    fn intels_keyframe_is_rewritten_to_slice_type_2_at_the_same_length() {
        let payload = join(&[QSV_SPS, QSV_PPS, QSV_IDR]);
        assert!(!idr_readable_when_encrypted(&payload));
        assert_eq!(idr_fields(&payload), [0, 7, 0, 0]);
        let rewritten = with_readable_pps_id(&payload).expect("rewritten");
        assert!(idr_readable_when_encrypted(&rewritten));
        assert_eq!(idr_fields(&rewritten), [0, 2, 0, 3]);
        // 1 011 1 00000000 00100: 18 bits as before, then the slice's own
        // bits from the 19th on, untouched.
        assert_eq!(
            rewritten,
            join(&[
                QSV_SPS,
                QSV_PPS,
                &[0, 0, 1, 0x25, 0xb8, 0x01, 0x0f, 0xff, 0xff, 0xd3, 0x14, 0x00, 0x04, 0x0e, 0x6a],
            ])
        );
    }

    #[test]
    fn every_idr_slice_of_the_picture_gets_the_same_new_id() {
        // first_mb 1 (010), slice type 7, PPS 0, frame_num 0, idr_pic_id 0.
        let second_slice: &[u8] = &[0, 0, 1, 0x25, 0b0100_0010, 0b0010_0000, 0b0001_0111, 0xf0];
        let payload = join(&[QSV_SPS, QSV_PPS, QSV_IDR, second_slice]);
        let rewritten = with_readable_pps_id(&payload).expect("rewritten");
        let units = nal_units(&rewritten);
        assert_eq!(units.len(), 4);
        let rbsp = unescape(&units[3].1[4..]);
        let mut bits = Bits::new(&rbsp);
        // first_mb 1, slice type 2, PPS 0, frame_num 0, idr_pic_id 3.
        let fields = [0; 3].map(|_| bits.exp_golomb().unwrap());
        assert_eq!(fields, [1, 2, 0]);
        bits.read(8).unwrap();
        assert_eq!(bits.exp_golomb(), Some(3));
    }

    #[test]
    fn a_readable_keyframe_or_one_without_its_sps_is_left_alone() {
        let idr = [0, 0, 0, 1, 0x65, 0b1011_1000, 0x40];
        assert_eq!(with_readable_pps_id(&join(&[SPS, PPS, &idr])), None);
        assert_eq!(with_readable_pps_id(DELTA), None);
        assert_eq!(with_readable_pps_id(&join(&[QSV_PPS, QSV_IDR])), None);
    }

    #[test]
    fn what_is_sent_is_readable_with_long_start_codes() {
        let sent = for_encryption(&join(&[QSV_SPS, QSV_PPS, QSV_IDR])).expect("rewritten");
        assert!(idr_readable_when_encrypted(&sent));
        assert!(start_codes(&sent).iter().all(|&(_, len)| len == 4));
        assert_eq!(for_encryption(&join(&[SPS, PPS, DELTA])), None);
    }

    #[test]
    fn longer_ids_stay_distinct() {
        for extra in [2, 4] {
            let ids: Vec<u32> = (0..2000).map(|id| longer_by(id, extra).unwrap()).collect();
            let mut unique = ids.clone();
            unique.sort();
            unique.dedup();
            assert_eq!(unique.len(), ids.len());
            for (id, longer) in ids.iter().enumerate() {
                assert_eq!(exp_golomb_len(*longer), exp_golomb_len(id as u32) + extra);
            }
        }
        assert_eq!(longer_by(65_535, 4), None);
    }

    #[test]
    fn emulation_prevention_comes_off_and_goes_back() {
        let rbsp = [0x25, 0, 0, 1, 0, 0, 0, 2, 0xff, 0, 0];
        let ebsp = escape(&rbsp);
        assert_eq!(ebsp, [0x25, 0, 0, 3, 1, 0, 0, 3, 0, 2, 0xff, 0, 0, 3]);
        assert_eq!(unescape(&ebsp[..ebsp.len() - 1]), rbsp);
    }

    #[test]
    fn a_delta_or_a_cut_off_idr_is_not_warned_about() {
        assert!(idr_readable_when_encrypted(DELTA));
        assert!(idr_readable_when_encrypted(&[0, 0, 0, 1, 0x65]));
    }

    #[test]
    fn units_are_split_at_both_start_code_forms() {
        let payload = join(&[SPS, PPS, IDR]);
        let kinds: Vec<u8> = nal_units(&payload).iter().map(|&(k, _)| k).collect();
        assert_eq!(kinds, vec![NAL_SPS, NAL_PPS, NAL_IDR]);
        assert_eq!(nal_units(&payload)[0].1, SPS);
        assert_eq!(nal_units(&payload)[2].1, IDR);
    }

    #[test]
    fn a_zero_byte_ending_a_unit_is_not_taken_for_a_start_code() {
        // A trailing zero before a three-byte start code reads as a
        // four-byte one; the unit before it loses only that zero.
        let payload = join(&[&[0, 0, 1, 0x41, 0x10, 0x00], &[0, 0, 1, 0x41, 0x20]]);
        let units = nal_units(&payload);
        assert_eq!(units.len(), 2);
        assert_eq!(units[0].1, &[0, 0, 1, 0x41, 0x10]);
    }

    #[test]
    fn an_idr_is_recognised_and_a_delta_is_not() {
        assert!(is_idr(&join(&[SPS, PPS, IDR])));
        assert!(!is_idr(DELTA));
        assert!(!is_idr(&[]));
    }

    #[test]
    fn a_bare_idr_gets_the_last_parameter_sets() {
        let mut sets = ParameterSets::default();
        let first = join(&[SPS, PPS, IDR]);
        assert_eq!(sets.complete(first.clone()), first);
        assert_eq!(sets.complete(DELTA.to_vec()), DELTA);
        assert_eq!(sets.complete(IDR.to_vec()), join(&[SPS, PPS, IDR]));
    }

    #[test]
    fn an_idr_before_any_parameter_sets_is_left_alone() {
        let mut sets = ParameterSets::default();
        assert_eq!(sets.complete(IDR.to_vec()), IDR);
    }

    #[test]
    fn short_start_codes_are_lengthened() {
        let payload = join(&[SPS, PPS, IDR]);
        let long = with_long_start_codes(&payload).expect("rewritten");
        assert_eq!(long, join(&[SPS, PPS, &[0], IDR]));
        assert!(start_codes(&long).iter().all(|&(_, len)| len == 4));
    }

    #[test]
    fn long_start_codes_are_left_alone() {
        assert_eq!(with_long_start_codes(&join(&[SPS, PPS, DELTA])), None);
        assert_eq!(with_long_start_codes(&[]), None);
    }

    #[test]
    fn only_the_missing_set_is_added() {
        let mut sets = ParameterSets::default();
        sets.complete(join(&[SPS, PPS, IDR]));
        let newer_pps: &[u8] = &[0, 0, 0, 1, 0x68, 0xee, 0x3c, 0x80];
        assert_eq!(
            sets.complete(join(&[newer_pps, IDR])),
            join(&[SPS, newer_pps, IDR])
        );
    }
}
