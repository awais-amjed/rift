//! H264 on an NVIDIA GPU through NVENC, on Linux.
//!
//! LiveKit has an NVENC encoder of its own, but it is built from NVIDIA's
//! Video Codec SDK samples, which are under NVIDIA's licence rather than one
//! the GPL client can carry. This talks to NVENC through `shiguredo_nvcodec`
//! instead: Apache-2.0, NVIDIA's MIT API header and nothing else of theirs,
//! with libcuda and libnvidia-encode opened at run time. A computer without
//! NVIDIA's driver simply has no encoder here.
//!
//! The same shape as the Windows encoder: pictures come in on a short queue,
//! newest kept; WebRTC's keyframe and bitrate requests are applied before each
//! one; encoded frames go straight to the [`EncodedSink`], from the crate's
//! own thread. NVENC works on a few pictures at once, so a picture that would
//! be one too many is dropped rather than queued behind it.
use super::h264::{self, ParameterSets};
use super::{clamp_bitrate, Encoded, EncodedSink, EncoderSettings, GpuCodec, Nv12Frame};
use shiguredo_nvcodec as nv;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

/// Pictures waiting for the encoder. Two is one going in and one behind it;
/// anything older is stale and better dropped.
const FRAME_QUEUE: usize = 2;

/// Pictures NVENC may hold at once. The crate keeps one more buffer than
/// this (`frame_interval_p + 3` with no B-frames), and reports a full one as
/// an error rather than waiting, so the count is kept here.
const IN_FLIGHT: usize = 3;

/// Frames between keyframes when nobody asks for one. WebRTC asks whenever a
/// viewer joins or loses packets, so this is only a safety net.
const GOP_SECONDS: u32 = 60;

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
    if codec != GpuCodec::H264 || !nv::is_cuda_library_available() {
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

fn device_name() -> String {
    nv::device_name(DEVICE).unwrap_or_else(|_| "an NVIDIA GPU".to_string())
}

/// A running NVENC encoder.
pub(crate) struct GpuEncoder {
    frames: Option<SyncSender<Nv12Frame>>,
    /// Picture buffers coming back from the encoder thread, to be filled again
    /// rather than allocated a frame at a time.
    spare: Arc<Mutex<Vec<Vec<u8>>>>,
    failed: Arc<AtomicBool>,
    /// The rate the encoder is at, for an encoder opened to take over.
    bitrate: Arc<AtomicU32>,
    handle: Option<JoinHandle<()>>,
    pub name: String,
}

impl GpuEncoder {
    /// Open NVENC for these settings and start feeding `sink`. `_only`, which
    /// picks one of several encoders on Windows, has nothing to pick here.
    pub(crate) fn open(
        settings: EncoderSettings,
        sink: Box<dyn EncodedSink>,
        _only: Option<usize>,
    ) -> Result<GpuEncoder, String> {
        if settings.codec != GpuCodec::H264 {
            return Err(format!("NVENC is not used for {} here", settings.codec));
        }
        #[cfg(test)]
        if super::test_hooks::NO_GPU.load(Ordering::Relaxed) {
            return Err("a test took the GPU away".to_string());
        }
        let (frames_tx, frames_rx) = mpsc::sync_channel(FRAME_QUEUE);
        let (opened_tx, opened_rx) = mpsc::channel();
        let spare = Arc::new(Mutex::new(Vec::new()));
        let failed = Arc::new(AtomicBool::new(false));
        let bitrate = Arc::new(AtomicU32::new(settings.start_bitrate_bps));
        let shared = Shared {
            spare: spare.clone(),
            failed: failed.clone(),
            bitrate: bitrate.clone(),
        };
        let handle = thread::Builder::new()
            .name("gpu-encoder".to_string())
            .spawn(move || encoder_thread(settings, sink, frames_rx, opened_tx, shared))
            .map_err(|e| format!("no encoder thread: {e}"))?;
        match opened_rx.recv() {
            Ok(Ok(name)) => Ok(GpuEncoder {
                frames: Some(frames_tx),
                spare,
                failed,
                bitrate,
                handle: Some(handle),
                name,
            }),
            Ok(Err(reason)) => {
                let _ = handle.join();
                Err(reason)
            }
            Err(_) => {
                let _ = handle.join();
                Err("the encoder thread ended before opening".to_string())
            }
        }
    }

    /// A buffer to convert the next picture into, at least `len` bytes.
    pub(crate) fn buffer(&self, len: usize) -> Vec<u8> {
        let mut buffer = self.spare.lock().unwrap().pop().unwrap_or_default();
        buffer.resize(len, 0);
        buffer
    }

    /// Queue a picture. A full queue means the encoder is behind; the picture
    /// is dropped, as the capture side drops its own when conversion lags.
    pub(crate) fn submit(&self, frame: Nv12Frame) {
        if let Some(frames) = &self.frames {
            match frames.try_send(frame) {
                Ok(()) => {}
                Err(TrySendError::Full(frame)) | Err(TrySendError::Disconnected(frame)) => {
                    self.spare.lock().unwrap().push(frame.data);
                }
            }
        }
    }

    /// Whether the encoder has stopped working. The share then has to move to
    /// another codec; this one will not recover.
    pub(crate) fn failed(&self) -> bool {
        self.failed.load(Ordering::Relaxed)
    }

    /// The rate WebRTC last asked for, inside the cap.
    pub(crate) fn bitrate(&self) -> u32 {
        self.bitrate.load(Ordering::Relaxed)
    }
}

impl Drop for GpuEncoder {
    fn drop(&mut self) {
        // Closing the queue is the stop signal.
        self.frames.take();
        if let Some(handle) = self.handle.take() {
            if handle.join().is_err() {
                log::warn!("encoder: thread panicked");
            }
        }
    }
}

/// What the encoder thread shares with the [`GpuEncoder`] that owns it.
struct Shared {
    spare: Arc<Mutex<Vec<Vec<u8>>>>,
    failed: Arc<AtomicBool>,
    bitrate: Arc<AtomicU32>,
}

/// The session settings for NVENC: constrained baseline, the profile LiveKit
/// offers for pre-encoded H264; no B-frames; tuned for the lowest latency;
/// variable bitrate from the start rate, moved by WebRTC's requests.
fn config(settings: &EncoderSettings) -> nv::EncoderConfig {
    let start = settings.start_bitrate_bps.min(settings.max_bitrate_bps);
    #[cfg(test)]
    let start = if super::test_hooks::IGNORE_RATE.load(Ordering::Relaxed) {
        settings.max_bitrate_bps
    } else {
        start
    };
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

fn encoder_thread(
    settings: EncoderSettings,
    sink: Box<dyn EncodedSink>,
    frames: Receiver<Nv12Frame>,
    opened: mpsc::Sender<Result<String, String>>,
    shared: Shared,
) {
    let sink = Arc::new(Mutex::new(sink));
    let in_flight = Arc::new(AtomicUsize::new(0));
    let output = Output {
        sink: sink.clone(),
        in_flight: in_flight.clone(),
        failed: shared.failed.clone(),
        parameter_sets: ParameterSets::default(),
    };
    let encoder = match nv::Encoder::new(config(&settings), output) {
        Ok(encoder) => encoder,
        Err(e) => {
            let _ = opened.send(Err(format!("NVENC did not open: {e}")));
            return;
        }
    };
    let name = format!("NVENC on {}", device_name());
    let _ = opened.send(Ok(name.clone()));

    let mut current = settings.start_bitrate_bps.min(settings.max_bitrate_bps);
    // The first picture, and any a viewer asks for, must be one it can start
    // from; a request that arrives while a picture is being dropped waits for
    // the next.
    let mut keyframe = true;
    #[cfg(test)]
    let mut fed = 0u32;
    while let Ok(frame) = frames.recv() {
        if shared.failed.load(Ordering::Relaxed) {
            break;
        }
        #[cfg(test)]
        {
            let fail_after = super::test_hooks::FAIL_AFTER.load(Ordering::Relaxed);
            if fail_after > 0 && fed >= fail_after {
                log::warn!("encoder: {name} stopped working: a test made it fail");
                shared.failed.store(true, Ordering::Relaxed);
                break;
            }
            fed += 1;
        }
        let (wanted_key, wanted_rate) = {
            let mut sink = sink.lock().unwrap();
            (sink.keyframe_wanted(), sink.bitrate_wanted())
        };
        keyframe |= wanted_key;
        if let Some(requested) = wanted_rate {
            let rate = clamp_bitrate(requested, settings.max_bitrate_bps);
            #[cfg(test)]
            if super::test_hooks::IGNORE_RATE.load(Ordering::Relaxed) {
                // Heard, so the rest of the share knows the target, but not
                // passed on.
                current = rate;
                shared.bitrate.store(rate, Ordering::Relaxed);
            }
            if rate != current {
                let params = nv::ReconfigureParams {
                    average_bitrate: Some(rate),
                    max_bitrate: Some(rate),
                    ..Default::default()
                };
                match encoder.reconfigure(params) {
                    Ok(()) => {
                        current = rate;
                        shared.bitrate.store(rate, Ordering::Relaxed);
                    }
                    Err(e) => log::warn!("encoder: moving the bitrate to {rate}: {e}"),
                }
            }
        }
        if in_flight.load(Ordering::Relaxed) >= IN_FLIGHT {
            shared.spare.lock().unwrap().push(frame.data);
            continue;
        }
        let options = nv::EncodeOptions {
            force_intra: false,
            force_idr: keyframe,
            output_spspps: keyframe,
        };
        in_flight.fetch_add(1, Ordering::Relaxed);
        // The crate copies the picture, so the buffer goes straight back.
        let result = encoder.encode(&frame.data, &options, frame.timestamp_us);
        shared.spare.lock().unwrap().push(frame.data);
        if let Err(e) = result {
            log::warn!("encoder: {name} stopped working: {e}");
            shared.failed.store(true, Ordering::Relaxed);
            break;
        }
        keyframe = false;
    }
    // Dropping it waits for NVENC to finish what it holds and closes it.
    drop(encoder);
    log::info!("encoder: {name} closed");
}

/// Where NVENC's encoded frames go, on the crate's own thread.
struct Output {
    sink: Arc<Mutex<Box<dyn EncodedSink>>>,
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
