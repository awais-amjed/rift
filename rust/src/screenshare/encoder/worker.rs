//! The thread a Linux GPU encoder runs on, whichever API it drives.
//!
//! Pictures come in on a short queue, newest kept; WebRTC's keyframe and
//! bitrate requests are applied before each one; encoded frames go to the
//! [`EncodedSink`]. What differs between NVENC and FFmpeg's VAAPI is only how
//! a picture is encoded and how the rate is moved: a [`Session`].
use super::{clamp_bitrate, EncodedSink, EncoderSettings, Nv12Frame};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

/// Pictures waiting for the encoder. Two is one going in and one behind it;
/// anything older is stale and better dropped.
const FRAME_QUEUE: usize = 2;

/// Frames between keyframes when nobody asks for one. WebRTC asks whenever a
/// viewer joins or loses packets, so this is only a safety net.
pub(super) const GOP_SECONDS: u32 = 60;

/// The sink, shared between the thread feeding the encoder and whichever
/// thread the encoder delivers on.
pub(super) type SharedSink = Arc<Mutex<Box<dyn EncodedSink>>>;

/// One open encoder, as the thread drives it.
pub(super) trait Session {
    /// Move the average rate; an error leaves the old one.
    fn set_bitrate(&mut self, bps: u32) -> Result<(), String>;
    /// Whether the encoder can take another picture now. One that would be
    /// one too many is dropped rather than queued behind the rest.
    fn ready(&self) -> bool {
        true
    }
    /// Encode a picture. What comes out goes to the sink, now or from the
    /// encoder's own thread. An error ends the share's use of the encoder.
    fn encode(&mut self, frame: &Nv12Frame, keyframe: bool) -> Result<(), String>;
}

/// How a backend opens its [`Session`], on the encoder thread: the session
/// and the encoder's name, or why it would not open.
pub(super) type Opener<S> =
    fn(&EncoderSettings, SharedSink, Arc<AtomicBool>) -> Result<(S, String), String>;

/// A running GPU encoder.
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
    /// Start an encoder thread, open the session on it with `open`, and wait
    /// until it has opened.
    pub(super) fn start<S: Session + 'static>(
        settings: EncoderSettings,
        sink: Box<dyn EncodedSink>,
        open: Opener<S>,
    ) -> Result<GpuEncoder, String> {
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
            .spawn(move || run(settings, sink, open, frames_rx, opened_tx, shared))
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

/// The rate an encoder opens at.
pub(super) fn start_bitrate(settings: &EncoderSettings) -> u32 {
    let start = settings.start_bitrate_bps.min(settings.max_bitrate_bps);
    #[cfg(test)]
    let start = if super::test_hooks::IGNORE_RATE.load(Ordering::Relaxed) {
        settings.max_bitrate_bps
    } else {
        start
    };
    start
}

fn run<S: Session>(
    settings: EncoderSettings,
    sink: Box<dyn EncodedSink>,
    open: Opener<S>,
    frames: Receiver<Nv12Frame>,
    opened: mpsc::Sender<Result<String, String>>,
    shared: Shared,
) {
    let sink: SharedSink = Arc::new(Mutex::new(sink));
    let (mut session, name) = match open(&settings, sink.clone(), shared.failed.clone()) {
        Ok(opened) => opened,
        Err(reason) => {
            let _ = opened.send(Err(reason));
            return;
        }
    };
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
                match session.set_bitrate(rate) {
                    Ok(()) => {
                        current = rate;
                        shared.bitrate.store(rate, Ordering::Relaxed);
                    }
                    Err(e) => log::warn!("encoder: moving the bitrate to {rate}: {e}"),
                }
            }
        }
        if !session.ready() {
            shared.spare.lock().unwrap().push(frame.data);
            continue;
        }
        let result = session.encode(&frame, keyframe);
        shared.spare.lock().unwrap().push(frame.data);
        if let Err(e) = result {
            log::warn!("encoder: {name} stopped working: {e}");
            shared.failed.store(true, Ordering::Relaxed);
            break;
        }
        keyframe = false;
    }
    // Dropping it finishes what the encoder holds and closes it.
    drop(session);
    log::info!("encoder: {name} closed");
}
