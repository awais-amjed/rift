//! Encoding the shared picture ourselves, on the GPU, where LiveKit's own
//! encoders would spend the CPU a game needs (`ARCHITECTURE.md`, "Encoding a
//! share on the GPU").
//!
//! On Windows through Media Foundation, which reaches NVIDIA's, AMD's and
//! Intel's encoders alike, since LiveKit has no hardware encoder there. On
//! Linux through NVENC (`nvenc.rs`), since LiveKit's own NVENC carries code
//! the GPL client cannot, and through FFmpeg's VAAPI encoder on Intel's and
//! AMD's GPUs (`ffmpeg.rs`), since LiveKit's own VAAPI encoder stalls. H264
//! and AV1 are only ever encoded by the GPU or the OS, never by Rift itself.
#![cfg_attr(not(gpu_encoder), allow(dead_code))]
// AV1 is made by the Windows encoder alone, and only in its tests.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub(crate) mod av1;
pub(crate) mod h264;
#[cfg(target_os = "windows")]
mod media_foundation;
#[cfg(target_os = "windows")]
pub(crate) use media_foundation::GpuEncoder;
#[cfg(target_os = "linux")]
mod ffmpeg;
#[cfg(target_os = "linux")]
mod nvenc;
#[cfg(target_os = "linux")]
mod worker;
#[cfg(target_os = "linux")]
pub(crate) use worker::GpuEncoder;

use super::resolution::Size;
use crate::api::screenshare::types::VideoCodec;

/// What the GPU encoder can be asked to make.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum GpuCodec {
    H264,
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    Av1,
}

impl GpuCodec {
    /// The GPU codec for a share's codec, if the GPU is what makes it. VP8
    /// and VP9 stay with libwebrtc's encoders on the CPU. AV1 is not a share
    /// codec yet: viewers cannot get it encrypted (`ARCHITECTURE.md`,
    /// "Encoding a share on the GPU").
    pub(crate) fn for_share(codec: VideoCodec) -> Option<GpuCodec> {
        match codec {
            VideoCodec::H264 => Some(GpuCodec::H264),
            VideoCodec::VP8 | VideoCodec::VP9 => None,
        }
    }
}

impl std::fmt::Display for GpuCodec {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            GpuCodec::H264 => "H264",
            GpuCodec::Av1 => "AV1",
        })
    }
}

/// The codecs this computer's GPU can make a share in. Opening an encoder to
/// find out takes a moment, and the GPUs do not change under a running app,
/// so the first answer is kept.
///
/// On Windows that is Rift's own encoder. On Linux it is Rift's NVENC, or
/// FFmpeg's VAAPI where NVIDIA's is missing; without either LiveKit would
/// make H264 with OpenH264 on the CPU, which Rift never does.
pub(crate) fn gpu_codecs() -> Vec<VideoCodec> {
    #[cfg(target_os = "windows")]
    {
        static CODECS: std::sync::OnceLock<Vec<VideoCodec>> = std::sync::OnceLock::new();
        CODECS
            .get_or_init(|| {
                if media_foundation::opens(GpuCodec::H264) {
                    vec![VideoCodec::H264]
                } else {
                    Vec::new()
                }
            })
            .clone()
    }
    #[cfg(target_os = "linux")]
    {
        if encodes_itself(GpuCodec::H264) {
            vec![VideoCodec::H264]
        } else {
            Vec::new()
        }
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        Vec::new()
    }
}

/// Whether a share in `codec` is encoded by Rift's own GPU encoder here. On
/// Windows always: a failure to open moves the share to VP9. On Linux where
/// NVENC or FFmpeg's VAAPI opens one, each asked once.
pub(crate) fn encodes_itself(codec: GpuCodec) -> bool {
    #[cfg(target_os = "linux")]
    {
        codec == GpuCodec::H264 && (nvenc_here() || ffmpeg::opens(codec))
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = codec;
        true
    }
}

/// Whether NVENC encodes H264 here, which on a computer with both is
/// preferred to VAAPI: asked once.
#[cfg(target_os = "linux")]
fn nvenc_here() -> bool {
    // A test on a computer with both runs VAAPI this way.
    #[cfg(test)]
    if std::env::var_os("GPU_NO_NVENC").is_some() {
        return false;
    }
    static NVENC: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *NVENC.get_or_init(|| nvenc::opens(GpuCodec::H264))
}

#[cfg(target_os = "linux")]
impl GpuEncoder {
    /// Open the GPU's encoder for these settings and start feeding `sink`:
    /// NVENC where NVIDIA's driver has one, else FFmpeg's VAAPI. `_only`,
    /// which picks one of several encoders on Windows, has nothing to pick
    /// here.
    pub(crate) fn open(
        settings: EncoderSettings,
        sink: Box<dyn EncodedSink>,
        _only: Option<usize>,
    ) -> Result<GpuEncoder, String> {
        if nvenc_here() {
            GpuEncoder::start(settings, sink, nvenc::open)
        } else {
            GpuEncoder::start(settings, sink, ffmpeg::open)
        }
    }
}

/// Ways for a test to make the GPU misbehave: be absent, or stop working
/// after so many pictures. Process-wide, like the share itself.
#[cfg(test)]
pub(crate) mod test_hooks {
    use std::sync::atomic::{AtomicBool, AtomicU32};

    pub(crate) static NO_GPU: AtomicBool = AtomicBool::new(false);
    /// 0 is never.
    pub(crate) static FAIL_AFTER: AtomicU32 = AtomicU32::new(0);
    /// The encoder stays at the share's cap whatever WebRTC asks for, as one
    /// that overshoots does. Linux's encoders only: they are the ones a bench
    /// can run on a capped link.
    pub(crate) static IGNORE_RATE: AtomicBool = AtomicBool::new(false);
}

/// The largest picture a hardware H264 encoder is sure to take: H264 level
/// 5.1's largest frame. AMD's (RX 9070 XT, Oct 5 2026) opened anything up to
/// 4096 wide and nothing wider, so a 5120x1440 screen shared at 2K or 4K went
/// out as VP9 on the CPU, at 178% of a core against 52% on the GPU. A share
/// bigger than this is scaled down to fit and stays on the GPU.
pub(crate) const MAX_SIZE: Size = Size {
    width: 4096,
    height: 2304,
};

/// The lowest bitrate the encoder is held to, whatever the connection asks
/// for: below this a 1080p picture is mush, and WebRTC's estimate climbs back
/// faster from a picture than from nothing.
const MIN_BITRATE_BPS: u32 = 150_000;

/// What the encoder is opened for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct EncoderSettings {
    pub codec: GpuCodec,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    /// The share's own cap; WebRTC's requests move the rate below it.
    pub max_bitrate_bps: u32,
    /// Where the rate starts until WebRTC first asks for one.
    pub start_bitrate_bps: u32,
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

/// One frame out of the encoder: an access unit in Annex B for H264, a
/// temporal unit of OBUs for AV1.
pub(crate) struct Encoded<'a> {
    pub codec: GpuCodec,
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
