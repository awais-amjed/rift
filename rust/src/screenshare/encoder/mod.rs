//! Encoding the shared picture ourselves, on the GPU, where LiveKit's own
//! encoders would spend the CPU a game needs (`ARCHITECTURE.md`, "Encoding a
//! share on the GPU").
//!
//! All through FFmpeg (`ffmpeg.rs`). On Windows, where LiveKit has no
//! hardware encoder, its NVENC, Quick Sync and AMF encoders on NVIDIA's,
//! Intel's and AMD's GPUs. On Linux its NVENC on NVIDIA's, since LiveKit's own
//! NVENC carries code the GPL client cannot, and its VAAPI encoder on Intel's
//! and AMD's, since LiveKit's own VAAPI encoder stalls. H264 is only ever
//! encoded by the GPU, never by Rift itself.
#![cfg_attr(not(gpu_encoder), allow(dead_code))]
#[cfg(any(target_os = "linux", target_os = "windows"))]
mod ffmpeg;
#[cfg(target_os = "linux")]
mod gpu_choice;
pub(crate) mod h264;
#[cfg(any(target_os = "linux", target_os = "windows"))]
mod timings;
#[cfg(any(target_os = "linux", target_os = "windows"))]
mod worker;
#[cfg(target_os = "linux")]
pub(crate) use ffmpeg::{dmabuf_target, library, symbol};
#[cfg(target_os = "linux")]
pub(crate) use gpu_choice::DmabufTarget;
#[cfg(any(target_os = "linux", target_os = "windows"))]
pub(crate) use worker::GpuEncoder;

#[cfg(target_os = "linux")]
use super::pw_stream::PwPicture;
use super::resolution::Size;
use crate::api::screenshare::types::VideoCodec;
#[cfg(target_os = "linux")]
use std::sync::Arc;

/// What the GPU encoder can be asked to make.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum GpuCodec {
    H264,
}

impl GpuCodec {
    /// The GPU codec for a share's codec, if the GPU is what makes it. VP8
    /// and VP9 stay with libwebrtc's encoders on the CPU.
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
        })
    }
}

/// The codecs this computer's GPU can make a share in: H264 where FFmpeg
/// opens one of its GPU encoders (`ffmpeg::opens`, asked once). Without one
/// LiveKit would make H264 with OpenH264 on the CPU, which Rift never does.
pub(crate) fn gpu_codecs() -> Vec<VideoCodec> {
    if encodes_itself(GpuCodec::H264) {
        vec![VideoCodec::H264]
    } else {
        Vec::new()
    }
}

/// Whether a share in `codec` is encoded by Rift's own GPU encoder here:
/// where FFmpeg opens one, asked once.
pub(crate) fn encodes_itself(codec: GpuCodec) -> bool {
    #[cfg(any(target_os = "linux", target_os = "windows"))]
    {
        ffmpeg::opens(codec)
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        let _ = codec;
        false
    }
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
impl GpuEncoder {
    /// Open FFmpeg's encoder for these settings, the first that opened
    /// (`ffmpeg::opens`), and start feeding `sink`.
    pub(crate) fn open(
        settings: EncoderSettings,
        sink: Box<dyn EncodedSink>,
    ) -> Result<GpuEncoder, String> {
        GpuEncoder::start(settings, sink, ffmpeg::open)
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
    /// that overshoots does (`worker.rs`).
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

/// Whether a GPU share's H264 goes out in High profile. Off since Oct 29
/// 2026: at a share's own rate High buys little (NVENC sent the same at
/// 15 Mbps), and a viewer decoding on the CPU, as every desktop one does,
/// pays 33 to 50% more for it. High itself works and stays tested
/// (`gpu_live_test.rs`); turn it on again once viewers decode on the GPU
/// (CALLS.md, "H264 in High profile").
pub(crate) const SEND_H264_HIGH: bool = false;

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
    /// H264's High profile rather than constrained baseline. The track is
    /// published asking for the same (`track::publish_video_track`).
    pub h264_high: bool,
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

/// A Wayland share's picture still on the GPU, as the compositor's DMA-BUF.
/// The encoder crops, turns, scales and places it there (`ffenc.h`), and
/// the buffer goes back to PipeWire once the GPU has copied it and the
/// processing thread has a newer picture (`capture_pw::process`).
#[cfg(target_os = "linux")]
pub(crate) struct DmaBufFrame {
    pub picture: Arc<PwPicture>,
    /// On the same clock as an [`Nv12Frame`]'s.
    pub timestamp_us: i64,
}

/// What the encoder is handed: a picture in memory, or one on the GPU.
pub(crate) enum EncoderInput {
    Nv12(Nv12Frame),
    #[cfg(target_os = "linux")]
    DmaBuf(DmaBufFrame),
}

impl EncoderInput {
    pub(crate) fn timestamp_us(&self) -> i64 {
        match self {
            EncoderInput::Nv12(frame) => frame.timestamp_us,
            #[cfg(target_os = "linux")]
            EncoderInput::DmaBuf(frame) => frame.timestamp_us,
        }
    }
}

/// One frame out of the encoder: an H264 access unit in Annex B.
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
