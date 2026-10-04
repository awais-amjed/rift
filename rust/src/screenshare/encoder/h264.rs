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
