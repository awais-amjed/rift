//! Windows' GPU encoder: FFmpeg's for NVIDIA's and Intel's GPUs, and Media
//! Foundation's for AMD's.
//!
//! Media Foundation stays only for what FFmpeg does not cover yet: AMD's GPUs
//! until FFmpeg's AMF encoder has been measured on one, and AV1, which only
//! its tests make. Where neither opens, a share goes out as VP9.
use super::media_foundation;
use super::{ffmpeg, worker, EncodedSink, EncoderSettings, GpuCodec, Nv12Frame};

/// A running GPU encoder, of either kind.
pub(crate) enum GpuEncoder {
    Ffmpeg(worker::GpuEncoder),
    MediaFoundation(media_foundation::GpuEncoder),
}

impl GpuEncoder {
    /// Open FFmpeg's encoder for these settings where it encodes them, else
    /// the first Media Foundation encoder a share may use that takes them, or
    /// the `only`th of those when one is named, and start feeding `sink`.
    pub(crate) fn open(
        settings: EncoderSettings,
        sink: Box<dyn EncodedSink>,
        only: Option<usize>,
    ) -> Result<GpuEncoder, String> {
        if only.is_none() && settings.codec == GpuCodec::H264 && ffmpeg::opens(settings.codec) {
            return worker::GpuEncoder::start(settings, sink, ffmpeg::open).map(GpuEncoder::Ffmpeg);
        }
        media_foundation::GpuEncoder::open(settings, sink, only).map(GpuEncoder::MediaFoundation)
    }

    pub(crate) fn name(&self) -> &str {
        match self {
            GpuEncoder::Ffmpeg(encoder) => encoder.name(),
            GpuEncoder::MediaFoundation(encoder) => &encoder.name,
        }
    }

    /// A buffer to convert the next picture into, at least `len` bytes.
    pub(crate) fn buffer(&self, len: usize) -> Vec<u8> {
        match self {
            GpuEncoder::Ffmpeg(encoder) => encoder.buffer(len),
            GpuEncoder::MediaFoundation(encoder) => encoder.buffer(len),
        }
    }

    /// Queue a picture, or drop it if the encoder is behind.
    pub(crate) fn submit(&self, frame: Nv12Frame) {
        match self {
            GpuEncoder::Ffmpeg(encoder) => encoder.submit(frame),
            GpuEncoder::MediaFoundation(encoder) => encoder.submit(frame),
        }
    }

    /// Whether the encoder has stopped working, for good.
    pub(crate) fn failed(&self) -> bool {
        match self {
            GpuEncoder::Ffmpeg(encoder) => encoder.failed(),
            GpuEncoder::MediaFoundation(encoder) => encoder.failed(),
        }
    }

    /// The rate WebRTC last asked for, inside the cap.
    pub(crate) fn bitrate(&self) -> u32 {
        match self {
            GpuEncoder::Ffmpeg(encoder) => encoder.bitrate(),
            GpuEncoder::MediaFoundation(encoder) => encoder.bitrate(),
        }
    }
}
