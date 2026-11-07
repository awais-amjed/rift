//! What an H265 access unit holds, read from its Annex B bytes: the same jobs
//! as `h264.rs`, for a NAL header of two bytes and three parameter sets.
//!
//! Nothing here rewrites a slice. H264 needed that because a receiver reads the
//! IDR's PPS id out of the bytes encryption leaves readable, and lost a keyframe
//! whenever that id fell past them. H265 loses none: 40 encrypted keyframes in
//! 20 s went through from Intel's and from NVIDIA's encoders with every picture
//! drawn (Nov 7 2026, `live_gpu_watch_h265_keyframes_survive_encryption`).
use super::h264;

/// NAL unit types this code acts on (H.265 table 7-1). 16 to 21 are the
/// pictures a decoder can start from: BLA, IDR and CRA.
const NAL_FIRST_RANDOM_ACCESS: u8 = 16;
const NAL_LAST_RANDOM_ACCESS: u8 = 21;
const NAL_VPS: u8 = 32;
const NAL_SPS: u8 = 33;
const NAL_PPS: u8 = 34;

/// The NAL units in an Annex B payload: each one's type and its bytes, start
/// code included.
fn nal_units(payload: &[u8]) -> Vec<(u8, &[u8])> {
    h264::nal_units(payload)
        .into_iter()
        .filter_map(|(_, unit)| {
            let header = *unit.get(h264::start_code_len(unit))?;
            Some((header >> 1 & 0x3f, unit))
        })
        .collect()
}

/// Whether the access unit starts a picture a viewer can decode from.
pub(crate) fn is_keyframe(payload: &[u8]) -> bool {
    nal_units(payload)
        .iter()
        .any(|&(kind, _)| is_random_access(kind))
}

fn is_random_access(kind: u8) -> bool {
    (NAL_FIRST_RANDOM_ACCESS..=NAL_LAST_RANDOM_ACCESS).contains(&kind)
}

/// The last VPS, SPS and PPS the encoder emitted.
#[derive(Default)]
pub(crate) struct ParameterSets {
    vps: Vec<u8>,
    sps: Vec<u8>,
    pps: Vec<u8>,
}

impl ParameterSets {
    /// Note the parameter sets in `payload`, and return it ready to send: a
    /// keyframe without them gets the last ones seen in front. Anything else
    /// is handed back as it is.
    pub(crate) fn complete(&mut self, payload: Vec<u8>) -> Vec<u8> {
        let (mut has_vps, mut has_sps, mut has_pps, mut key) = (false, false, false, false);
        for &(kind, bytes) in &nal_units(&payload) {
            match kind {
                NAL_VPS => {
                    has_vps = true;
                    self.vps = bytes.to_vec();
                }
                NAL_SPS => {
                    has_sps = true;
                    self.sps = bytes.to_vec();
                }
                NAL_PPS => {
                    has_pps = true;
                    self.pps = bytes.to_vec();
                }
                kind if is_random_access(kind) => key = true,
                _ => {}
            }
        }
        if !key || (has_vps && has_sps && has_pps) {
            return payload;
        }
        if self.vps.is_empty() || self.sps.is_empty() || self.pps.is_empty() {
            return payload;
        }
        let mut whole =
            Vec::with_capacity(self.vps.len() + self.sps.len() + self.pps.len() + payload.len());
        if !has_vps {
            whole.extend_from_slice(&self.vps);
        }
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

    // A NAL header is the type shifted left one bit, then the layer and
    // temporal id: 0x40 0x01 is a VPS, and so on.
    const VPS: &[u8] = &[0, 0, 0, 1, 0x40, 0x01, 0x0c];
    const SPS: &[u8] = &[0, 0, 0, 1, 0x42, 0x01, 0x01];
    const PPS: &[u8] = &[0, 0, 0, 1, 0x44, 0x01, 0xc0];
    const IDR: &[u8] = &[0, 0, 1, 0x26, 0x01, 0xaf];
    const CRA: &[u8] = &[0, 0, 0, 1, 0x2a, 0x01, 0xaf];
    const TRAIL: &[u8] = &[0, 0, 0, 1, 0x02, 0x01, 0xd0];

    fn join(parts: &[&[u8]]) -> Vec<u8> {
        parts.concat()
    }

    #[test]
    fn the_type_comes_from_the_first_header_byte() {
        let payload = join(&[VPS, SPS, PPS, IDR, TRAIL]);
        let kinds: Vec<u8> = nal_units(&payload).iter().map(|&(k, _)| k).collect();
        assert_eq!(kinds, [32, 33, 34, 19, 1]);
    }

    #[test]
    fn a_decoder_can_start_from_idr_and_cra_only() {
        assert!(is_keyframe(&join(&[VPS, SPS, PPS, IDR])));
        assert!(is_keyframe(CRA));
        assert!(!is_keyframe(TRAIL));
        assert!(!is_keyframe(&join(&[VPS, SPS, PPS])));
        assert!(!is_keyframe(&[]));
    }

    #[test]
    fn a_bare_keyframe_gets_the_last_parameter_sets() {
        let mut sets = ParameterSets::default();
        let first = join(&[VPS, SPS, PPS, IDR]);
        assert_eq!(sets.complete(first.clone()), first);
        assert_eq!(sets.complete(TRAIL.to_vec()), TRAIL);
        assert_eq!(sets.complete(IDR.to_vec()), join(&[VPS, SPS, PPS, IDR]));
    }

    #[test]
    fn only_the_missing_sets_are_added() {
        let mut sets = ParameterSets::default();
        sets.complete(join(&[VPS, SPS, PPS, IDR]));
        let newer: &[u8] = &[0, 0, 0, 1, 0x44, 0x01, 0xc1];
        assert_eq!(
            sets.complete(join(&[newer, IDR])),
            join(&[VPS, SPS, newer, IDR])
        );
    }

    #[test]
    fn a_keyframe_before_any_parameter_sets_is_left_alone() {
        let mut sets = ParameterSets::default();
        assert_eq!(sets.complete(IDR.to_vec()), IDR);
    }

    #[test]
    fn its_start_codes_are_lengthened_like_h264s() {
        let long = h264::with_long_start_codes(&join(&[VPS, IDR])).expect("rewritten");
        assert_eq!(long, join(&[VPS, &[0], IDR]));
    }
}
