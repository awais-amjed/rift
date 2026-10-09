//! The GPU path of a share: pictures in NV12 to the hardware encoder, its
//! H264 or AV1 out to a pre-encoded LiveKit source, and WebRTC's keyframe and
//! bitrate requests back the other way. Pictures the encoder would make too
//! much of are left out on the way in ([`RateGate`]).
use super::encoder::{
    h264, Encoded, EncodedSink, EncoderSettings, GpuCodec, GpuEncoder, Nv12Frame,
};
use super::rate_gate::RateGate;
use super::resolution::Size;
use livekit::webrtc::native::yuv_helper;
use livekit::webrtc::prelude::I420Buffer;
use livekit::webrtc::video_frame::{EncodedFrameType, EncodedVideoCodec, EncodedVideoFrame};
use livekit::webrtc::video_source::native::NativeVideoSource;
use livekit::webrtc::video_source::VideoResolution;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

/// A running GPU encoder, and what to do if it stops working.
pub(crate) struct GpuFeed {
    encoder: GpuEncoder,
    /// Called once, from the processing thread, when the encoder fails.
    on_failed: Box<dyn Fn() + Send + Sync>,
    reported: AtomicBool,
    /// What the encoder has made against WebRTC's target, filled from the
    /// encoder's side and asked before each picture.
    gate: Arc<Mutex<RateGate>>,
}

impl GpuFeed {
    /// Open the first hardware encoder that takes these settings, feeding
    /// `source`. Blocks while the encoder opens.
    pub(crate) fn open(
        source: &NativeVideoSource,
        settings: EncoderSettings,
        on_failed: Box<dyn Fn() + Send + Sync>,
    ) -> Result<GpuFeed, String> {
        let gate = Arc::new(Mutex::new(RateGate::new()));
        let encoder = GpuEncoder::open(
            settings,
            Box::new(SourceSink {
                source: source.clone(),
                resolution: VideoResolution {
                    width: settings.width,
                    height: settings.height,
                },
                gate: gate.clone(),
            }),
            None,
        )?;
        Ok(GpuFeed {
            encoder,
            on_failed,
            reported: AtomicBool::new(false),
            gate,
        })
    }

    pub(crate) fn name(&self) -> &str {
        self.encoder.name()
    }

    /// The rate the encoder is at, which one taking over starts from.
    pub(crate) fn bitrate(&self) -> u32 {
        self.encoder.bitrate()
    }

    /// Hand the encoder one picture, already the target size in I420 or
    /// still the native size in ARGB. Says false once the encoder has failed,
    /// having told the session so the first time.
    pub(crate) fn send(&self, picture: Picture<'_>, target: Size, timestamp_us: i64) -> bool {
        if self.encoder.failed() {
            if !self.reported.swap(true, Ordering::Relaxed) {
                (self.on_failed)();
            }
            return false;
        }
        if !self.admits() {
            return true;
        }
        let width = target.width as usize;
        let height = target.height as usize;
        let mut data = self
            .encoder
            .buffer(Nv12Frame::len_for(target.width, target.height));
        let (y, uv) = data.split_at_mut(width * height);
        match picture {
            Picture::Argb { data: argb, stride } => yuv_helper::argb_to_nv12(
                argb,
                stride,
                y,
                target.width,
                uv,
                target.width,
                target.width as i32,
                target.height as i32,
            ),
            Picture::I420(buffer) => {
                let (stride_y, stride_u, stride_v) = buffer.strides();
                let (src_y, src_u, src_v) = buffer.data();
                yuv_helper::i420_to_nv12(
                    src_y,
                    stride_y,
                    src_u,
                    stride_u,
                    src_v,
                    stride_v,
                    y,
                    target.width,
                    uv,
                    target.width,
                    target.width as i32,
                    target.height as i32,
                );
            }
        }
        self.encoder.submit(Nv12Frame { data, timestamp_us });
        true
    }

    /// Whether the encoder is within WebRTC's target, so the next picture
    /// may go to it.
    fn admits(&self) -> bool {
        let now = Instant::now();
        let target = self.encoder.bitrate();
        let mut gate = self.gate.lock().unwrap();
        if let Some(left_out) = gate.report(now) {
            log::info!(
                "screenshare: left out {left_out} pictures to keep {} within {target} bps",
                self.encoder.name()
            );
        }
        gate.admits(target, now)
    }
}

/// One captured picture, in whichever form it is when it reaches the target
/// size.
pub(crate) enum Picture<'a> {
    Argb { data: &'a [u8], stride: u32 },
    I420(&'a I420Buffer),
}

/// The pre-encoded source, as the encoder sees it.
struct SourceSink {
    source: NativeVideoSource,
    resolution: VideoResolution,
    gate: Arc<Mutex<RateGate>>,
}

/// Frames handed to LiveKit, for a test to set against what WebRTC says it
/// sent: the difference is frames WebRTC dropped on the way.
#[cfg(test)]
pub(crate) static DELIVERED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

impl EncodedSink for SourceSink {
    fn deliver(&mut self, frame: Encoded<'_>) {
        #[cfg(test)]
        DELIVERED.fetch_add(1, Ordering::Relaxed);
        let (codec, long) = match frame.codec {
            // So the receiver authenticates the same bytes the sender
            // encrypted.
            GpuCodec::H264 => (
                EncodedVideoCodec::H264,
                h264::with_long_start_codes(frame.payload),
            ),
            GpuCodec::Av1 => (EncodedVideoCodec::AV1, None),
        };
        self.gate
            .lock()
            .unwrap()
            .spent(frame.payload.len(), Instant::now());
        self.source.capture_encoded_frame(&EncodedVideoFrame {
            codec,
            payload: long.as_deref().unwrap_or(frame.payload),
            timestamp_us: frame.timestamp_us,
            frame_type: if frame.keyframe {
                EncodedFrameType::Key
            } else {
                EncodedFrameType::Delta
            },
            resolution: self.resolution.clone(),
            frame_metadata: None,
        });
    }

    fn keyframe_wanted(&mut self) -> bool {
        self.source.take_keyframe_request()
    }

    fn bitrate_wanted(&mut self) -> Option<u64> {
        self.source
            .take_rate_control_request()
            .map(|request| request.target_bitrate_bps)
    }
}
