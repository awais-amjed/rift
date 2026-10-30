//! The GPU path of a share: pictures in NV12 to the hardware encoder, its
//! H264 out to a pre-encoded LiveKit source, and WebRTC's keyframe and
//! bitrate requests back the other way. Pictures the encoder would make too
//! much of are left out on the way in ([`RateGate`]).
use super::encoder::{h264, Encoded, EncodedSink, EncoderSettings, GpuEncoder, Nv12Frame};
#[cfg(target_os = "linux")]
use super::encoder::{DmaBufFrame, EncoderInput};
use super::pixels::ByteOrder;
#[cfg(target_os = "linux")]
use super::pw_stream::PwPicture;
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
                warned_unreadable: false,
            }),
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

    /// Whether the encoder takes a Wayland share's DMA-BUF whole: VAAPI's
    /// does, NVENC's takes the picture from memory.
    #[cfg(target_os = "linux")]
    pub(crate) fn takes_dmabuf(&self) -> bool {
        self.encoder.takes_dmabuf()
    }

    /// What to call, from the encoder's thread, with the format and modifier
    /// of a DMA-BUF the GPU would not read.
    #[cfg(target_os = "linux")]
    pub(crate) fn on_import_failed(&self, told: Box<dyn Fn(u32, u64) + Send + Sync>) {
        self.encoder.on_import_failed(told);
    }

    /// The rate the encoder is at, which one taking over starts from.
    pub(crate) fn bitrate(&self) -> u32 {
        self.encoder.bitrate()
    }

    /// Hand the encoder one picture, already the target size in I420, still
    /// the native size in ARGB, or a DMA-BUF the encoder fits itself. Says
    /// whether the encoder took it: not when the rate gate left it out, nor
    /// once the encoder has failed, having told the session so the first
    /// time.
    pub(crate) fn send(&self, picture: Picture<'_>, target: Size, timestamp_us: i64) -> bool {
        if self.encoder.failed() {
            if !self.reported.swap(true, Ordering::Relaxed) {
                (self.on_failed)();
            }
            return false;
        }
        if !self.admits() {
            return false;
        }
        let picture = match picture {
            #[cfg(target_os = "linux")]
            Picture::DmaBuf(picture) => {
                self.encoder.submit_input(EncoderInput::DmaBuf(DmaBufFrame {
                    picture,
                    timestamp_us,
                }));
                return true;
            }
            picture => picture,
        };
        let width = target.width as usize;
        let height = target.height as usize;
        let mut data = self
            .encoder
            .buffer(Nv12Frame::len_for(target.width, target.height));
        let (y, uv) = data.split_at_mut(width * height);
        match picture {
            Picture::Packed {
                data: packed,
                stride,
                order,
            } => {
                let to_nv12 = match order {
                    ByteOrder::Bgrx => yuv_helper::argb_to_nv12,
                    ByteOrder::Rgbx => yuv_helper::abgr_to_nv12,
                };
                to_nv12(
                    packed,
                    stride,
                    y,
                    target.width,
                    uv,
                    target.width,
                    target.width as i32,
                    target.height as i32,
                )
            }
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
            #[cfg(target_os = "linux")]
            Picture::DmaBuf(_) => unreachable!("sent whole above"),
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
        if let Some(report) = gate.report(now) {
            let average_kb = if report.keyframes > 0 {
                report.keyframe_bytes / u64::from(report.keyframes) / 1000
            } else {
                0
            };
            log::info!(
                "screenshare: left out {} pictures ({} within 1 s of a keyframe) to keep {} \
                 within {target} bps; keyframes: {}, {average_kb} KB average",
                report.left_out,
                report.left_out_after_keyframes,
                self.encoder.name(),
                report.keyframes,
            );
        }
        gate.admits(target, now)
    }
}

/// One captured picture, in whichever form it is when it reaches the target
/// size: or a Wayland share's DMA-BUF, sent to the encoder whole.
pub(crate) enum Picture<'a> {
    /// Four bytes a pixel, in `order`.
    Packed {
        data: &'a [u8],
        stride: u32,
        order: ByteOrder,
    },
    I420(&'a I420Buffer),
    /// Shared with the processing thread, which keeps the newest picture
    /// until a feed takes it.
    #[cfg(target_os = "linux")]
    DmaBuf(Arc<PwPicture>),
}

/// The pre-encoded source, as the encoder sees it.
struct SourceSink {
    source: NativeVideoSource,
    resolution: VideoResolution,
    gate: Arc<Mutex<RateGate>>,
    /// Whether the log has been told this encoder's keyframes are lost to
    /// encrypted viewers ([`h264::idr_readable_when_encrypted`]); once is
    /// enough.
    warned_unreadable: bool,
}

/// Frames handed to LiveKit, for a test to set against what WebRTC says it
/// sent: the difference is frames WebRTC dropped on the way.
#[cfg(test)]
pub(crate) static DELIVERED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

impl EncodedSink for SourceSink {
    fn deliver(&mut self, frame: Encoded<'_>) {
        #[cfg(test)]
        DELIVERED.fetch_add(1, Ordering::Relaxed);
        // So the receiver authenticates the same bytes the sender encrypted,
        // and can find a keyframe's PPS.
        let rewritten = h264::for_encryption(frame.payload);
        let payload = rewritten.as_deref().unwrap_or(frame.payload);
        if frame.keyframe && !self.warned_unreadable && !h264::idr_readable_when_encrypted(payload)
        {
            log::warn!(
                "screenshare: this encoder's keyframes put the slice's PPS id past what \
                 encryption leaves readable, and could not be rewritten; encrypted viewers \
                 will drop about half of them"
            );
            self.warned_unreadable = true;
        }
        self.gate
            .lock()
            .unwrap()
            .spent(frame.payload.len(), frame.keyframe, Instant::now());
        self.source.capture_encoded_frame(&EncodedVideoFrame {
            codec: EncodedVideoCodec::H264,
            payload,
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
