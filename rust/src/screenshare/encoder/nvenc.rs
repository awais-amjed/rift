//! H264 on an NVIDIA GPU through NVENC, on Linux.
//!
//! LiveKit has an NVENC encoder of its own, but it is built from NVIDIA's
//! Video Codec SDK samples, which are under NVIDIA's licence rather than one
//! the GPL client can carry. This talks to NVENC through `shiguredo_nvcodec`
//! instead: Apache-2.0, NVIDIA's MIT API header and nothing else of theirs,
//! with libcuda and libnvidia-encode opened at run time. A computer without
//! NVIDIA's driver simply has no encoder here.
//!
//! Driven from the shared encoder thread (`worker.rs`). NVENC works on a few
//! pictures at once and delivers on the crate's own thread.
use super::h264::{self, ParameterSets};
use super::worker::{self, Session, SharedSink, GOP_SECONDS};
use super::{Encoded, EncoderSettings, GpuCodec, Nv12Frame};
use shiguredo_nvcodec as nv;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;

/// Pictures NVENC may hold at once. The crate keeps one more buffer than
/// this (`frame_interval_p + 3` with no B-frames), and reports a full one as
/// an error rather than waiting, so the count is kept here.
const IN_FLIGHT: usize = 3;

/// The GPU NVENC runs on: the first CUDA device, which on a laptop with two
/// GPUs is the NVIDIA one whichever drives the screen.
const DEVICE: i32 = 0;

/// Whether NVENC will encode `codec` here: NVIDIA's driver is installed and
/// its first GPU has an encoder for it. Asked once, by `gpu_codecs`.
pub(crate) fn opens(codec: GpuCodec) -> bool {
    #[cfg(test)]
    if super::test_hooks::NO_GPU.load(Ordering::Relaxed) {
        return false;
    }
    if codec != GpuCodec::H264 || !cuda_starts() {
        return false;
    }
    match nv::query_encoder_caps(nv::EncoderCodec::H264, DEVICE) {
        Ok(caps) => {
            log::info!(
                "encoder: NVENC on {} encodes H264 up to {}x{}",
                device_name(),
                caps.width_max,
                caps.height_max
            );
            true
        }
        Err(e) => {
            log::info!("encoder: no NVENC here: {e}");
            false
        }
    }
}

/// Whether CUDA starts here and sees a GPU. Asked before the crate is: when
/// `cuInit` fails, the crate names the error by loading CUDA again from inside
/// its own first load, and waits on itself for ever (shiguredo_nvcodec
/// 2026.2.0). That happens wherever NVIDIA's driver is installed but its GPU
/// is not there: switched off on a laptop, or hidden with
/// `CUDA_VISIBLE_DEVICES` (Oct 9 2026). Once `cuInit` has worked, it works
/// again inside the crate.
fn cuda_starts() -> bool {
    // SAFETY: NVIDIA's driver library, which runs nothing on load that an
    // NVIDIA-using process does not run anyway.
    let Ok(cuda) = (unsafe { libloading::Library::new("libcuda.so.1") }) else {
        return false;
    };
    // SAFETY: both functions have these types in every CUDA driver API
    // version, and the count is written before it is read.
    unsafe {
        let Ok(init) = cuda.get::<unsafe extern "C" fn(u32) -> u32>(b"cuInit\0") else {
            return false;
        };
        let Ok(count) = cuda.get::<unsafe extern "C" fn(*mut i32) -> u32>(b"cuDeviceGetCount\0")
        else {
            return false;
        };
        let status = init(0);
        if status != 0 {
            log::info!("encoder: no NVENC here: CUDA did not start ({status})");
            return false;
        }
        let mut devices = 0;
        count(&mut devices) == 0 && devices > 0
    }
}

fn device_name() -> String {
    nv::device_name(DEVICE).unwrap_or_else(|_| "an NVIDIA GPU".to_string())
}

/// The session settings for NVENC: constrained baseline, the profile LiveKit
/// offers for pre-encoded H264; no B-frames; tuned for the lowest latency;
/// variable bitrate from the start rate, moved by WebRTC's requests.
fn config(settings: &EncoderSettings) -> nv::EncoderConfig {
    let start = worker::start_bitrate(settings);
    nv::EncoderConfig {
        codec: nv::CodecConfig::H264(nv::H264EncoderConfig {
            profile: Some(nv::H264Profile::Baseline),
            idr_period: None,
        }),
        width: settings.width,
        height: settings.height,
        max_encode_width: None,
        max_encode_height: None,
        framerate_num: settings.fps,
        framerate_den: 1,
        average_bitrate: Some(start),
        preset: nv::Preset::P4,
        tuning_info: nv::TuningInfo::ULTRA_LOW_LATENCY,
        rate_control_mode: nv::RateControlMode::Vbr,
        gop_length: Some(settings.fps * GOP_SECONDS),
        frame_interval_p: 1,
        buffer_format: nv::BufferFormat::Nv12,
        device_id: DEVICE,
    }
}

/// NVENC opened for a share, as the encoder thread drives it.
pub(super) struct NvencSession {
    encoder: nv::Encoder<Output>,
    in_flight: Arc<AtomicUsize>,
}

/// Open NVENC for these settings, delivering to `sink`.
pub(super) fn open(
    settings: &EncoderSettings,
    sink: SharedSink,
    failed: Arc<AtomicBool>,
) -> Result<(NvencSession, String), String> {
    if settings.codec != GpuCodec::H264 {
        return Err(format!("NVENC is not used for {} here", settings.codec));
    }
    let in_flight = Arc::new(AtomicUsize::new(0));
    let output = Output {
        sink,
        in_flight: in_flight.clone(),
        failed,
        parameter_sets: ParameterSets::default(),
    };
    let encoder = nv::Encoder::new(config(settings), output)
        .map_err(|e| format!("NVENC did not open: {e}"))?;
    Ok((
        NvencSession { encoder, in_flight },
        format!("NVENC on {}", device_name()),
    ))
}

impl Session for NvencSession {
    fn set_bitrate(&mut self, bps: u32) -> Result<(), String> {
        let params = nv::ReconfigureParams {
            average_bitrate: Some(bps),
            max_bitrate: Some(bps),
            ..Default::default()
        };
        self.encoder.reconfigure(params).map_err(|e| e.to_string())
    }

    fn ready(&self) -> bool {
        self.in_flight.load(Ordering::Relaxed) < IN_FLIGHT
    }

    fn encode(&mut self, frame: &Nv12Frame, keyframe: bool) -> Result<(), String> {
        let options = nv::EncodeOptions {
            force_intra: false,
            force_idr: keyframe,
            output_spspps: keyframe,
        };
        self.in_flight.fetch_add(1, Ordering::Relaxed);
        // The crate copies the picture, so the buffer can go straight back.
        self.encoder
            .encode(&frame.data, &options, frame.timestamp_us)
            .map_err(|e| e.to_string())
    }
}

/// Where NVENC's encoded frames go, on the crate's own thread.
struct Output {
    sink: SharedSink,
    in_flight: Arc<AtomicUsize>,
    failed: Arc<AtomicBool>,
    /// An IDR the encoder sent without SPS and PPS gets the last ones put
    /// back in front, since a viewer can only start from one that has them.
    parameter_sets: ParameterSets,
}

impl nv::EncodeHandler for Output {
    /// The picture's capture time, in microseconds.
    type UserData = i64;
    type Error = nv::Error;

    fn on_encoded(&mut self, result: Result<nv::EncodedFrame<i64>, nv::Error>) {
        self.in_flight.fetch_sub(1, Ordering::Relaxed);
        match result {
            Ok(frame) => {
                let (payload, timestamp_us) = frame.into_parts();
                let keyframe = h264::is_idr(&payload);
                let payload = self.parameter_sets.complete(payload);
                self.sink.lock().unwrap().deliver(Encoded {
                    codec: GpuCodec::H264,
                    payload: &payload,
                    timestamp_us,
                    keyframe,
                });
            }
            Err(e) => {
                log::warn!("encoder: NVENC failed a picture: {e}");
                self.failed.store(true, Ordering::Relaxed);
            }
        }
    }
}
