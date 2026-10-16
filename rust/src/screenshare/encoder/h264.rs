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
        let code = if unit.starts_with(&[0, 0, 0, 1]) {
            4
        } else {
            3
        };
        whole.extend_from_slice(&[0, 0, 0, 1]);
        whole.extend_from_slice(&unit[code..]);
    }
    Some(whole)
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
    // from the bytes after the NAL header.
    let mut bits = Bits::new(&unit[start_code_len(unit) + 1..]);
    for _ in 0..3 {
        if bits.exp_golomb().is_none() {
            // Too short to tell; nothing to warn about.
            return true;
        }
    }
    bits.at <= 8
}

/// The access unit with each IDR slice's type said in the short form (7 as 2,
/// 9 as 4), so [`idr_readable_when_encrypted`] holds; `None` when there is
/// nothing to shorten, or the slices are not ones this can rewrite.
///
/// FFmpeg's patch (`third_party/ffmpeg/RIFT_PATCHES.md`) is enough where FFmpeg
/// writes the slice header. AMD's VCN writes its own whatever it is handed,
/// always type 7 and `idr_pic_id` 0 (Mesa 26.2.4 on an RX 9070 XT, Oct 16
/// 2026), so the header is rewritten here. To leave every bit after it where
/// it was — the slice data, and CABAC's byte alignment — the bits the shorter
/// type saves go to a longer `idr_pic_id`: v becomes v + (2^z − 1)·2^k, which
/// has z more leading zeros, and different ids stay different, which is all a
/// decoder asks of two IDRs in a row.
fn with_short_idr_slice_types(payload: &[u8], sps: &[u8]) -> Option<Vec<u8>> {
    let layout = SliceLayout::of_sps(&rbsp(&sps[start_code_len(sps) + 1..]))?;
    let units = nal_units(payload);
    let mut rewritten = Vec::with_capacity(units.len());
    let mut saved = None;
    for &(kind, unit) in &units {
        if kind != NAL_IDR {
            rewritten.push(None);
            continue;
        }
        let code = start_code_len(unit);
        let mut body = rbsp(&unit[code + 1..]);
        let bits = layout.shorten(&mut body)?;
        // Every slice of a picture has the same idr_pic_id, so every one
        // must have been moved by the same amount.
        if *saved.get_or_insert(bits) != bits {
            return None;
        }
        let mut whole = unit[..code + 1].to_vec();
        whole.extend_from_slice(&escaped(&body));
        rewritten.push(Some(whole));
    }
    saved?;
    let mut whole = Vec::with_capacity(payload.len() + 8);
    for ((_, unit), new) in units.iter().zip(&rewritten) {
        whole.extend_from_slice(new.as_deref().unwrap_or(unit));
    }
    Some(whole)
}

/// What an IDR slice header holds between its type and `idr_pic_id`, from the
/// SPS (H.264 7.3.2.1.1 and 7.3.3).
struct SliceLayout {
    separate_colour_planes: bool,
    frame_num_bits: u32,
    frame_mbs_only: bool,
}

impl SliceLayout {
    fn of_sps(sps: &[u8]) -> Option<SliceLayout> {
        let mut bits = Bits::new(sps);
        let profile = bits.read(8)?;
        bits.read(16)?; // constraint flags, level
        bits.exp_golomb()?; // seq_parameter_set_id
        let mut separate_colour_planes = false;
        if matches!(
            profile,
            100 | 110 | 122 | 244 | 44 | 83 | 86 | 118 | 128 | 138 | 139 | 134 | 135
        ) {
            if bits.exp_golomb()? == 3 {
                separate_colour_planes = bits.read(1)? == 1;
            }
            bits.exp_golomb()?; // bit depths
            bits.exp_golomb()?;
            bits.read(1)?; // qpprime_y_zero_transform_bypass_flag
            if bits.read(1)? == 1 {
                // Scaling lists: none of Rift's encoders send them.
                return None;
            }
        }
        let frame_num_bits = bits.exp_golomb()? + 4;
        match bits.exp_golomb()? {
            0 => {
                bits.exp_golomb()?;
            }
            1 => {
                bits.read(1)?;
                // se(v) is as long as ue(v), so both step over the same way.
                bits.exp_golomb()?;
                bits.exp_golomb()?;
                for _ in 0..bits.exp_golomb()? {
                    bits.exp_golomb()?;
                }
            }
            _ => {}
        }
        bits.exp_golomb()?; // max_num_ref_frames
        bits.read(1)?; // gaps_in_frame_num_value_allowed_flag
        bits.exp_golomb()?; // width and height
        bits.exp_golomb()?;
        let frame_mbs_only = bits.read(1)? == 1;
        Some(SliceLayout {
            separate_colour_planes,
            frame_num_bits,
            frame_mbs_only,
        })
    }

    /// Rewrite the header at the start of an IDR slice's RBSP in place, and
    /// say how many bits went from its type to its `idr_pic_id`.
    fn shorten(&self, body: &mut [u8]) -> Option<u32> {
        let mut bits = Bits::new(body);
        let first_mb = bits.exp_golomb()?;
        let slice_type = bits.exp_golomb()?;
        let pps_id = bits.exp_golomb()?;
        let colour_plane = if self.separate_colour_planes {
            Some(bits.read(2)?)
        } else {
            None
        };
        let frame_num = bits.read(self.frame_num_bits)?;
        let mut field = Vec::new();
        if !self.frame_mbs_only {
            let field_pic = bits.read(1)?;
            field.push(field_pic);
            if field_pic == 1 {
                field.push(bits.read(1)?);
            }
        }
        let idr_pic_id = bits.exp_golomb()?;
        let end = bits.at;
        if slice_type < 5 {
            return None;
        }
        let short = slice_type - 5;
        let saved = exp_golomb_len(slice_type) - exp_golomb_len(short);
        let zeros = saved / 2;
        let leading = exp_golomb_len(idr_pic_id) / 2;
        let longer = idr_pic_id + ((1 << zeros) - 1) * (1 << leading);
        // idr_pic_id is at most 65535 (7.4.3).
        if longer > 65535 {
            return None;
        }
        let mut out = BitWriter::new(body);
        out.exp_golomb(first_mb);
        out.exp_golomb(short);
        out.exp_golomb(pps_id);
        if let Some(plane) = colour_plane {
            out.write(plane, 2);
        }
        out.write(frame_num, self.frame_num_bits);
        for flag in field {
            out.write(flag, 1);
        }
        out.exp_golomb(longer);
        debug_assert_eq!(out.at, end);
        Some(saved)
    }
}

/// How many bits ue(v) takes for `value`.
fn exp_golomb_len(value: u32) -> u32 {
    2 * (32 - (value + 1).leading_zeros() - 1) + 1
}

/// A NAL unit's payload without its emulation prevention bytes.
fn rbsp(escaped: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(escaped.len());
    let mut zeros = 0;
    for &byte in escaped {
        if zeros >= 2 && byte == 3 {
            zeros = 0;
            continue;
        }
        zeros = if byte == 0 { zeros + 1 } else { 0 };
        out.push(byte);
    }
    out
}

/// An RBSP with emulation prevention bytes put back (H.264 7.4.1).
fn escaped(rbsp: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(rbsp.len() + rbsp.len() / 64);
    let mut zeros = 0;
    for &byte in rbsp {
        if zeros >= 2 && byte <= 3 {
            out.push(3);
            zeros = 0;
        }
        zeros = if byte == 0 { zeros + 1 } else { 0 };
        out.push(byte);
    }
    if out.last() == Some(&0) {
        out.push(3);
    }
    out
}

fn start_code_len(unit: &[u8]) -> usize {
    if unit.starts_with(&[0, 0, 0, 1]) {
        4
    } else {
        3
    }
}

/// A reader of the leading bits of an SPS or a slice header. It reads the
/// bytes as they are: [`idr_readable_when_encrypted`] needs only the first
/// two after the NAL header, where no emulation prevention byte can fall, and
/// the rest is handed an RBSP.
struct Bits<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Bits<'a> {
    fn new(bytes: &'a [u8]) -> Bits<'a> {
        Bits { bytes, at: 0 }
    }

    fn bit(&mut self) -> Option<u32> {
        let byte = self.bytes.get(self.at / 8)?;
        let bit = byte >> (7 - self.at % 8) & 1;
        self.at += 1;
        Some(bit.into())
    }

    fn read(&mut self, count: u32) -> Option<u32> {
        let mut value = 0;
        for _ in 0..count {
            value = value << 1 | self.bit()?;
        }
        Some(value)
    }

    /// One ue(v): as many zeros, a one, then as many bits again.
    fn exp_golomb(&mut self) -> Option<u32> {
        let mut zeros = 0;
        while self.bit()? == 0 {
            zeros += 1;
            if zeros > 31 {
                return None;
            }
        }
        Some((1u32 << zeros) - 1 + self.read(zeros)?)
    }
}

/// Writes bits over the start of a buffer, leaving the rest of it as it was.
struct BitWriter<'a> {
    bytes: &'a mut [u8],
    at: usize,
}

impl<'a> BitWriter<'a> {
    fn new(bytes: &'a mut [u8]) -> BitWriter<'a> {
        BitWriter { bytes, at: 0 }
    }

    fn write(&mut self, value: u32, count: u32) {
        for i in (0..count).rev() {
            let mask = 0x80 >> (self.at % 8);
            if value >> i & 1 == 1 {
                self.bytes[self.at / 8] |= mask;
            } else {
                self.bytes[self.at / 8] &= !mask;
            }
            self.at += 1;
        }
    }

    fn exp_golomb(&mut self, value: u32) {
        let len = exp_golomb_len(value);
        self.write(0, len / 2);
        self.write(value + 1, len / 2 + 1);
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
    /// IDR without them gets the last ones seen in front, and one whose PPS id
    /// encryption would hide has its slice types shortened
    /// ([`with_short_idr_slice_types`]). Anything else is handed back as it is.
    pub(crate) fn complete(&mut self, payload: Vec<u8>) -> Vec<u8> {
        let whole = self.with_parameter_sets(payload);
        if self.sps.is_empty() || idr_readable_when_encrypted(&whole) {
            return whole;
        }
        with_short_idr_slice_types(&whole, &self.sps).unwrap_or(whole)
    }

    fn with_parameter_sets(&mut self, payload: Vec<u8>) -> Vec<u8> {
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

    /// The parameter sets and the start of the first IDR from AMD's VCN
    /// (Mesa 26.2.4, RX 9070 XT) through FFmpeg's VAAPI encoder, Oct 16 2026.
    /// The SPS has emulation prevention bytes in it.
    const AMD_SPS: &[u8] = &[
        0, 0, 0, 1, 0x67, 0x42, 0x40, 0x2a, 0x95, 0xa0, 0x1e, 0x00, 0x89, 0xf9, 0x66, 0xa0, 0xc0,
        0xc0, 0xc8, 0x00, 0x00, 0x03, 0x00, 0x08, 0x00, 0x00, 0x03, 0x03, 0xc4, 0x78, 0x44, 0x23,
        0x50,
    ];
    const AMD_PPS: &[u8] = &[0, 0, 0, 1, 0x68, 0xce, 0x38, 0x80];
    /// first_mb 0, slice_type 7, pps_id 0, frame_num 0 (8 bits), idr_pic_id 0:
    /// 18 bits, the PPS id ending at the ninth.
    const AMD_IDR: &[u8] = &[
        0, 0, 0, 1, 0x65, 0x88, 0x80, 0x42, 0x88, 0xc0, 0x38, 0x98, 0x33, 0x80, 0x00, 0x89,
    ];

    #[test]
    fn an_amd_idr_is_rewritten_to_short_slice_types_and_the_same_length() {
        let mut sets = ParameterSets::default();
        let before = join(&[AMD_SPS, AMD_PPS, AMD_IDR]);
        assert!(!idr_readable_when_encrypted(&before));
        let after = sets.complete(before.clone());
        assert!(idr_readable_when_encrypted(&after));
        // first_mb 0 (1), slice_type 2 (011), pps_id 0 (1), frame_num 0
        // (00000000), idr_pic_id 3 (00100): 18 bits again, and every bit
        // after them where it was.
        let idr = [
            0, 0, 0, 1, 0x65, 0xb8, 0x01, 0x02, 0x88, 0xc0, 0x38, 0x98, 0x33, 0x80, 0x00, 0x89,
        ];
        assert_eq!(after, join(&[AMD_SPS, AMD_PPS, &idr]));
    }

    #[test]
    fn a_bare_amd_idr_is_rewritten_with_the_sps_seen_before() {
        let mut sets = ParameterSets::default();
        sets.complete(join(&[AMD_SPS, AMD_PPS, AMD_IDR]));
        let after = sets.complete(AMD_IDR.to_vec());
        assert!(idr_readable_when_encrypted(&after));
        assert_eq!(after.len(), join(&[AMD_SPS, AMD_PPS, AMD_IDR]).len());
    }

    #[test]
    fn every_slice_of_the_idr_is_rewritten_alike() {
        let mut sets = ParameterSets::default();
        let after = sets.complete(join(&[AMD_SPS, AMD_PPS, AMD_IDR, AMD_IDR]));
        let slices: Vec<&[u8]> = nal_units(&after)
            .into_iter()
            .filter(|&(kind, _)| kind == NAL_IDR)
            .map(|(_, unit)| unit)
            .collect();
        assert_eq!(slices.len(), 2);
        assert_eq!(slices[0], slices[1]);
        assert_eq!(slices[0][5], 0xb8);
    }

    #[test]
    fn an_idr_whose_slices_disagree_is_left_alone() {
        // The second slice already says type 2: moving only the first one's
        // idr_pic_id would give the picture two.
        let short = [0, 0, 0, 1, 0x65, 0b1011_1000, 0x00, 0x80];
        let payload = join(&[AMD_SPS, AMD_PPS, AMD_IDR, &short]);
        assert_eq!(ParameterSets::default().complete(payload.clone()), payload);
    }

    #[test]
    fn a_longer_idr_pic_id_keeps_ids_apart_and_takes_the_bits_saved() {
        for saved in [2, 4] {
            let zeros = saved / 2;
            let ids: Vec<u32> = (0..200)
                .map(|id| id + ((1 << zeros) - 1) * (1 << (exp_golomb_len(id) / 2)))
                .collect();
            for (id, &longer) in ids.iter().enumerate() {
                assert_eq!(
                    exp_golomb_len(longer),
                    exp_golomb_len(id as u32) + saved,
                    "{id}"
                );
            }
            let mut sorted = ids.clone();
            sorted.dedup();
            assert_eq!(sorted.len(), ids.len());
        }
    }

    #[test]
    fn exp_golomb_is_written_as_it_is_read() {
        for value in [0, 1, 2, 3, 6, 7, 14, 15, 255, 65535] {
            let mut bytes = [0xffu8; 8];
            let mut out = BitWriter::new(&mut bytes);
            out.exp_golomb(value);
            let written = out.at;
            let mut bits = Bits::new(&bytes);
            assert_eq!(bits.exp_golomb(), Some(value));
            assert_eq!(bits.at, written);
            assert_eq!(written as u32, exp_golomb_len(value));
        }
    }

    #[test]
    fn emulation_prevention_is_taken_out_and_put_back() {
        let escaped_bytes = [0x00, 0x00, 0x03, 0x01, 0x42, 0x00, 0x00, 0x03, 0x00, 0x07];
        let raw = rbsp(&escaped_bytes);
        assert_eq!(raw, [0x00, 0x00, 0x01, 0x42, 0x00, 0x00, 0x00, 0x07]);
        assert_eq!(escaped(&raw), escaped_bytes);
        assert_eq!(escaped(&[0x12, 0x00, 0x00]), [0x12, 0x00, 0x00, 0x03]);
    }
}
