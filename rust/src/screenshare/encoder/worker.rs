//! The thread a GPU encoder runs on: FFmpeg's, on Linux and Windows.
//!
//! One picture waits for the encoder, and a newer one replaces it, since a
//! picture that waited behind a newer one is only delay. WebRTC's keyframe and
//! bitrate requests are applied before each one; encoded frames go to the
//! [`EncodedSink`]. How a picture is encoded and how the rate is moved is the
//! encoder's: a [`Session`].
//!
//! A Wayland compositor sends a picture only when the screen changes, so on a
//! still screen the encoder hears nothing, while a viewer joining still needs
//! a keyframe and WebRTC still wants a frame now and then. The last picture
//! is encoded again then: at once when a keyframe is wanted, and after
//! [`REPEAT_AFTER`] of quiet otherwise.
use super::{clamp_bitrate, EncodedSink, EncoderInput, EncoderSettings, Nv12Frame};
use crate::screenshare::latest::{self, Putter, Taker};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

/// Frames between keyframes when nobody asks for one. WebRTC asks whenever a
/// viewer joins or loses packets, so this is only a safety net.
pub(super) const GOP_SECONDS: u32 = 60;

/// How long a still screen goes before its last picture is encoded again.
pub(super) const REPEAT_AFTER: Duration = Duration::from_secs(1);

/// How often a quiet encoder asks whether a keyframe is wanted.
pub(super) const KEYFRAME_POLL: Duration = Duration::from_millis(100);

/// The sink, as the encoder thread and its session share it.
pub(super) type SharedSink = Arc<Mutex<Box<dyn EncodedSink>>>;

/// Why a picture was not encoded.
#[derive(Debug)]
pub(super) enum EncodeError {
    /// The encoder stopped working; the share moves to another codec.
    Failed(String),
    /// The GPU would not read a DMA-BUF in this format and modifier. The
    /// picture is dropped, and the capture asks the compositor for another
    /// modifier; the encoder carries on. Only Linux has DMA-BUFs.
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    ImportFailed { drm_format: u32, modifier: u64 },
}

/// One open encoder, as the thread drives it.
pub(super) trait Session {
    /// Move the average rate; an error leaves the old one.
    fn set_bitrate(&mut self, bps: u32) -> Result<(), String>;
    /// Encode a picture. What comes out goes to the sink, now or from the
    /// encoder's own thread.
    fn encode(&mut self, input: &EncoderInput, keyframe: bool) -> Result<(), EncodeError>;
    /// Encode the last picture again, for a still screen: true if it did,
    /// false with none it can repeat (one from memory is not kept). An error
    /// ends the share's use of the encoder.
    fn repeat(&mut self, timestamp_us: i64, keyframe: bool) -> Result<bool, String>;
    /// Whether it takes [`EncoderInput::DmaBuf`]; one that does not fails on
    /// it.
    fn takes_dmabuf(&self) -> bool;
}

/// What a [`GpuEncoder`] is told of a DMA-BUF the GPU would not read: its
/// format and modifier.
type ImportFailed = Box<dyn Fn(u32, u64) + Send + Sync>;

/// A running GPU encoder.
pub(crate) struct GpuEncoder {
    frames: Option<Putter<EncoderInput>>,
    /// Picture buffers coming back from the encoder thread, to be filled again
    /// rather than allocated a frame at a time.
    spare: Arc<Mutex<Vec<Vec<u8>>>>,
    failed: Arc<AtomicBool>,
    /// The rate the encoder is at, for an encoder opened to take over.
    bitrate: Arc<AtomicU32>,
    // Read by the Wayland capture, which only Linux has.
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    import_failed: Arc<Mutex<Option<ImportFailed>>>,
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    takes_dmabuf: bool,
    handle: Option<JoinHandle<()>>,
    pub name: String,
}

impl GpuEncoder {
    /// Start an encoder thread, open the session on it with `open`, and wait
    /// until it has opened. `open` gives the session and the encoder's name,
    /// or why it would not open.
    pub(super) fn start<S, F>(
        settings: EncoderSettings,
        sink: Box<dyn EncodedSink>,
        open: F,
    ) -> Result<GpuEncoder, String>
    where
        S: Session + 'static,
        F: FnOnce(&EncoderSettings, SharedSink) -> Result<(S, String), String> + Send + 'static,
    {
        #[cfg(test)]
        if super::test_hooks::NO_GPU.load(Ordering::Relaxed) {
            return Err("a test took the GPU away".to_string());
        }
        let (frames_tx, frames_rx) = latest::channel();
        let (opened_tx, opened_rx) = mpsc::channel();
        let spare = Arc::new(Mutex::new(Vec::new()));
        let failed = Arc::new(AtomicBool::new(false));
        let bitrate = Arc::new(AtomicU32::new(settings.start_bitrate_bps));
        let import_failed = Arc::new(Mutex::new(None));
        let shared = Shared {
            spare: spare.clone(),
            failed: failed.clone(),
            bitrate: bitrate.clone(),
            import_failed: import_failed.clone(),
        };
        let handle = thread::Builder::new()
            .name("gpu-encoder".to_string())
            .spawn(move || run(settings, sink, open, frames_rx, opened_tx, shared))
            .map_err(|e| format!("no encoder thread: {e}"))?;
        match opened_rx.recv() {
            Ok(Ok((name, takes_dmabuf))) => Ok(GpuEncoder {
                frames: Some(frames_tx),
                spare,
                failed,
                bitrate,
                import_failed,
                takes_dmabuf,
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

    /// Leave a picture for the encoder. One still waiting means the encoder is
    /// behind; that older one is dropped, as the capture side drops its own
    /// when conversion lags.
    pub(crate) fn submit(&self, frame: Nv12Frame) {
        self.submit_input(EncoderInput::Nv12(frame));
    }

    /// [`submit`](Self::submit), for a picture in memory or on the GPU. A
    /// DMA-BUF dropped here goes back to PipeWire.
    pub(crate) fn submit_input(&self, input: EncoderInput) {
        if let Some(frames) = &self.frames {
            if let Some(dropped) = frames.put(input) {
                recycle(&self.spare, dropped);
            }
        }
    }

    /// Whether the encoder takes a DMA-BUF: VAAPI's does, NVENC's does not.
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    pub(crate) fn takes_dmabuf(&self) -> bool {
        self.takes_dmabuf
    }

    /// What to call, from the encoder's thread, with the format and modifier
    /// of a DMA-BUF the GPU would not read.
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    pub(crate) fn on_import_failed(&self, told: ImportFailed) {
        *self.import_failed.lock().unwrap() = Some(told);
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

    pub(crate) fn name(&self) -> &str {
        &self.name
    }
}

impl Drop for GpuEncoder {
    fn drop(&mut self) {
        // Closing the mailbox is the stop signal.
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
    import_failed: Arc<Mutex<Option<ImportFailed>>>,
}

/// A picture done with: its buffer kept for the next, or its DMA-BUF given
/// back.
fn recycle(spare: &Mutex<Vec<Vec<u8>>>, input: EncoderInput) {
    match input {
        EncoderInput::Nv12(frame) => spare.lock().unwrap().push(frame.data),
        #[cfg(target_os = "linux")]
        EncoderInput::DmaBuf(frame) => drop(frame),
    }
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

fn run<S, F>(
    settings: EncoderSettings,
    sink: Box<dyn EncodedSink>,
    open: F,
    frames: Taker<EncoderInput>,
    opened: mpsc::Sender<Result<(String, bool), String>>,
    shared: Shared,
) where
    S: Session,
    F: FnOnce(&EncoderSettings, SharedSink) -> Result<(S, String), String>,
{
    let sink: SharedSink = Arc::new(Mutex::new(sink));
    let (mut session, name) = match open(&settings, sink.clone()) {
        Ok(opened) => opened,
        Err(reason) => {
            let _ = opened.send(Err(reason));
            return;
        }
    };
    let _ = opened.send(Ok((name.clone(), session.takes_dmabuf())));

    let mut current = settings.start_bitrate_bps.min(settings.max_bitrate_bps);
    // The first picture, and any a viewer asks for, must be one it can start
    // from; a request that arrives while a picture is being dropped waits for
    // the next.
    let mut keyframe = true;
    // The last picture encoded, its timestamp and when: what a still screen
    // repeats, and how long it has been still.
    let mut last: Option<(i64, Instant)> = None;
    // That picture, when it came from memory: the session keeps a DMA-BUF's
    // to repeat itself, but not one of these, and a still Wayland screen
    // sends nothing more.
    let mut kept: Option<Nv12Frame> = None;
    #[cfg(test)]
    let mut fed = 0u32;
    loop {
        let input = frames.take_timeout(KEYFRAME_POLL);
        if input.is_none() && frames.closed() {
            break;
        }
        if shared.failed.load(Ordering::Relaxed) {
            break;
        }
        #[cfg(test)]
        if input.is_some() {
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

        let Some(input) = input else {
            // A still screen.
            let Some((timestamp_us, at)) = last else {
                continue;
            };
            let still = at.elapsed();
            if !keyframe && still < REPEAT_AFTER {
                continue;
            }
            let timestamp_us = timestamp_us + still.as_micros() as i64;
            match session.repeat(timestamp_us, keyframe) {
                Ok(true) => {
                    keyframe = false;
                    last = Some((timestamp_us, Instant::now()));
                }
                // The session keeps no picture from memory: this thread does.
                Ok(false) if kept.is_some() => {
                    let mut frame = kept.take().unwrap();
                    frame.timestamp_us = timestamp_us;
                    let input = EncoderInput::Nv12(frame);
                    let result = session.encode(&input, keyframe);
                    kept = match input {
                        EncoderInput::Nv12(frame) => Some(frame),
                        #[cfg(target_os = "linux")]
                        EncoderInput::DmaBuf(_) => None,
                    };
                    match result {
                        Ok(()) => {
                            keyframe = false;
                            last = Some((timestamp_us, Instant::now()));
                        }
                        Err(EncodeError::Failed(e)) => {
                            log::warn!("encoder: {name} stopped working: {e}");
                            shared.failed.store(true, Ordering::Relaxed);
                            break;
                        }
                        // Only a DMA-BUF is imported.
                        Err(EncodeError::ImportFailed { .. }) => {}
                    }
                }
                // Nothing kept to repeat: the next picture is the keyframe.
                Ok(false) => last = None,
                Err(e) => {
                    log::warn!("encoder: {name} stopped working: {e}");
                    shared.failed.store(true, Ordering::Relaxed);
                    break;
                }
            }
            continue;
        };
        let timestamp_us = input.timestamp_us();
        let result = session.encode(&input, keyframe);
        match input {
            EncoderInput::Nv12(frame) if result.is_ok() => {
                if let Some(older) = kept.replace(frame) {
                    recycle(&shared.spare, EncoderInput::Nv12(older));
                }
            }
            input => {
                // A DMA-BUF encoded is the session's to repeat now.
                if result.is_ok() {
                    if let Some(older) = kept.take() {
                        recycle(&shared.spare, EncoderInput::Nv12(older));
                    }
                }
                recycle(&shared.spare, input);
            }
        }
        match result {
            Ok(()) => {
                keyframe = false;
                last = Some((timestamp_us, Instant::now()));
            }
            Err(EncodeError::ImportFailed {
                drm_format,
                modifier,
            }) => {
                log::info!(
                    "encoder: {name} cannot read format {drm_format:#x} with modifier \
                     {modifier:#x}; the picture is dropped"
                );
                if let Some(told) = &*shared.import_failed.lock().unwrap() {
                    told(drm_format, modifier);
                }
            }
            Err(EncodeError::Failed(e)) => {
                log::warn!("encoder: {name} stopped working: {e}");
                shared.failed.store(true, Ordering::Relaxed);
                break;
            }
        }
    }
    // Dropping it finishes what the encoder holds and closes it.
    drop(session);
    log::info!("encoder: {name} closed");
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::screenshare::encoder::{Encoded, GpuCodec};
    use std::sync::atomic::AtomicBool;
    use std::time::{Duration, Instant};

    /// What the fake encoder was asked to do.
    #[derive(Default)]
    struct Asked {
        pictures: u32,
        /// Each repeat, and whether it was a keyframe.
        repeats: Vec<bool>,
    }

    struct FakeSession {
        asked: Arc<Mutex<Asked>>,
        /// Every picture fails to import, with this format and modifier.
        import_fails: Option<(u32, u64)>,
        /// Whether it keeps a picture to repeat, as VAAPI keeps a DMA-BUF's;
        /// a picture from memory it does not.
        repeats_itself: bool,
    }

    impl Session for FakeSession {
        fn set_bitrate(&mut self, _bps: u32) -> Result<(), String> {
            Ok(())
        }

        fn encode(&mut self, _input: &EncoderInput, _keyframe: bool) -> Result<(), EncodeError> {
            if let Some((drm_format, modifier)) = self.import_fails {
                return Err(EncodeError::ImportFailed {
                    drm_format,
                    modifier,
                });
            }
            self.asked.lock().unwrap().pictures += 1;
            Ok(())
        }

        fn repeat(&mut self, _timestamp_us: i64, keyframe: bool) -> Result<bool, String> {
            if !self.repeats_itself {
                return Ok(false);
            }
            self.asked.lock().unwrap().repeats.push(keyframe);
            Ok(true)
        }

        fn takes_dmabuf(&self) -> bool {
            true
        }
    }

    struct FakeSink {
        keyframe: Arc<AtomicBool>,
    }

    impl EncodedSink for FakeSink {
        fn deliver(&mut self, _frame: Encoded<'_>) {}

        fn keyframe_wanted(&mut self) -> bool {
            self.keyframe.swap(false, Ordering::Relaxed)
        }

        fn bitrate_wanted(&mut self) -> Option<u64> {
            None
        }
    }

    const SETTINGS: EncoderSettings = EncoderSettings {
        codec: GpuCodec::H264,
        width: 64,
        height: 64,
        fps: 30,
        max_bitrate_bps: 1_000_000,
        start_bitrate_bps: 1_000_000,
        h264_high: false,
    };

    /// A fake encoder, what it is asked, and the sink's keyframe request.
    fn fake(import_fails: Option<(u32, u64)>) -> (GpuEncoder, Arc<Mutex<Asked>>, Arc<AtomicBool>) {
        fake_session(import_fails, true)
    }

    fn fake_session(
        import_fails: Option<(u32, u64)>,
        repeats_itself: bool,
    ) -> (GpuEncoder, Arc<Mutex<Asked>>, Arc<AtomicBool>) {
        let asked = Arc::new(Mutex::new(Asked::default()));
        let keyframe = Arc::new(AtomicBool::new(false));
        let session = FakeSession {
            asked: asked.clone(),
            import_fails,
            repeats_itself,
        };
        let encoder = GpuEncoder::start(
            SETTINGS,
            Box::new(FakeSink {
                keyframe: keyframe.clone(),
            }),
            move |_: &EncoderSettings, _: SharedSink| Ok((session, "fake".to_string())),
        )
        .unwrap();
        (encoder, asked, keyframe)
    }

    fn picture() -> EncoderInput {
        EncoderInput::Nv12(Nv12Frame {
            data: vec![0; Nv12Frame::len_for(64, 64)],
            timestamp_us: 1,
        })
    }

    /// Waits up to `within` for `done` to hold.
    fn until(within: Duration, mut done: impl FnMut() -> bool) -> bool {
        let start = Instant::now();
        while start.elapsed() < within {
            if done() {
                return true;
            }
            thread::sleep(Duration::from_millis(5));
        }
        done()
    }

    #[test]
    fn a_still_screen_is_repeated_each_second() {
        let (encoder, asked, _) = fake(None);
        encoder.submit_input(picture());
        assert!(until(Duration::from_millis(200), || asked
            .lock()
            .unwrap()
            .pictures
            == 1));
        thread::sleep(Duration::from_millis(2200));
        let asked = asked.lock().unwrap();
        assert_eq!(asked.repeats, vec![false, false]);
        assert_eq!(asked.pictures, 1);
    }

    #[test]
    fn a_keyframe_request_on_a_still_screen_repeats_at_once() {
        let (encoder, asked, keyframe) = fake(None);
        encoder.submit_input(picture());
        assert!(until(Duration::from_millis(200), || asked
            .lock()
            .unwrap()
            .pictures
            == 1));
        keyframe.store(true, Ordering::Relaxed);
        assert!(until(Duration::from_millis(150), || {
            asked.lock().unwrap().repeats == vec![true]
        }));
    }

    #[test]
    fn a_still_picture_from_memory_is_encoded_again() {
        // NVENC takes every picture from memory and keeps none to repeat, and
        // a GNOME screen that is still sends nothing more.
        let (encoder, asked, keyframe) = fake_session(None, false);
        encoder.submit_input(picture());
        assert!(until(Duration::from_millis(200), || asked
            .lock()
            .unwrap()
            .pictures
            == 1));
        // A viewer joining asks for a keyframe: it gets the picture at once.
        keyframe.store(true, Ordering::Relaxed);
        assert!(until(Duration::from_millis(150), || asked
            .lock()
            .unwrap()
            .pictures
            == 2));
        // And once a second while nothing new comes.
        thread::sleep(Duration::from_millis(1200));
        assert_eq!(asked.lock().unwrap().pictures, 3);
        assert!(!encoder.failed());
    }

    #[test]
    fn an_import_failure_drops_the_picture_and_keeps_the_encoder() {
        let (encoder, asked, _) = fake(Some((0x3432_5258, 0x0100_0000_0000_0002)));
        let (told_tx, told_rx) = mpsc::channel();
        let told_tx = Mutex::new(told_tx);
        encoder.on_import_failed(Box::new(move |drm_format, modifier| {
            let _ = told_tx.lock().unwrap().send((drm_format, modifier));
        }));
        encoder.submit_input(picture());
        let told = told_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        assert_eq!(told, (0x3432_5258, 0x0100_0000_0000_0002));
        assert!(!encoder.failed());
        // Nothing was encoded, so a still screen has nothing to repeat.
        thread::sleep(Duration::from_millis(1200));
        assert!(asked.lock().unwrap().repeats.is_empty());
        assert!(!encoder.failed());
    }
}
