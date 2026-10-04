//! Encoding the shared picture ourselves, on the GPU, where LiveKit's own
//! encoders would spend the CPU a game needs (`GPU_ENCODING.md`).
//!
//! Windows only for now: LiveKit has no hardware encoder there, and Media
//! Foundation reaches NVIDIA's, AMD's and Intel's alike. H264 is only ever
//! encoded by the GPU or the OS, never by Rift itself (decision 1 of the plan).
#![cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub(crate) mod h264;
#[cfg(target_os = "windows")]
mod media_foundation;
#[cfg(target_os = "windows")]
#[allow(unused_imports)]
pub(crate) use media_foundation::{hardware_h264_encoders, GpuEncoder};

/// The lowest bitrate the encoder is held to, whatever the connection asks
/// for: below this a 1080p picture is mush, and WebRTC's estimate climbs back
/// faster from a picture than from nothing.
const MIN_BITRATE_BPS: u32 = 150_000;

/// What the encoder is opened for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct EncoderSettings {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    /// The share's own cap; WebRTC's requests move the rate below it.
    pub max_bitrate_bps: u32,
}

/// A picture to encode: `width * height` bytes of Y, then the interleaved U
/// and V at half size (NV12, the layout hardware encoders take), tightly
/// packed.
pub(crate) struct Nv12Frame {
    pub data: Vec<u8>,
    /// When it was captured, in microseconds: carried through the encoder so
    /// the viewer's clock follows the capture, not the encoder's latency.
    pub timestamp_us: i64,
}

impl Nv12Frame {
    pub(crate) fn len_for(width: u32, height: u32) -> usize {
        width as usize * height as usize * 3 / 2
    }
}

/// One access unit out of the encoder, as Annex B.
pub(crate) struct Encoded<'a> {
    pub payload: &'a [u8],
    pub timestamp_us: i64,
    pub keyframe: bool,
}

/// Where encoded frames go, and where WebRTC's requests come from. In a share
/// this is the pre-encoded video source; in a test, a recorder.
pub(crate) trait EncodedSink: Send + 'static {
    fn deliver(&mut self, frame: Encoded<'_>);
    /// A viewer needs a picture it can start from: one joined, or lost packets.
    fn keyframe_wanted(&mut self) -> bool;
    /// What the connection can carry now, when WebRTC's estimate has moved.
    fn bitrate_wanted(&mut self) -> Option<u64>;
}

/// The rate to give the encoder for what WebRTC asked: never above the
/// share's cap, never below [`MIN_BITRATE_BPS`].
pub(crate) fn clamp_bitrate(requested_bps: u64, max_bps: u32) -> u32 {
    let floor = MIN_BITRATE_BPS.min(max_bps);
    requested_bps.clamp(u64::from(floor), u64::from(max_bps)) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_bitrate_follows_the_request_inside_the_cap() {
        assert_eq!(clamp_bitrate(4_000_000, 10_000_000), 4_000_000);
        assert_eq!(clamp_bitrate(40_000_000, 10_000_000), 10_000_000);
        assert_eq!(clamp_bitrate(0, 10_000_000), MIN_BITRATE_BPS);
    }

    #[test]
    fn a_cap_under_the_floor_wins() {
        assert_eq!(clamp_bitrate(0, 100_000), 100_000);
    }

    #[test]
    fn an_nv12_picture_is_one_and_a_half_bytes_a_pixel() {
        assert_eq!(Nv12Frame::len_for(1920, 1080), 3_110_400);
    }
}
