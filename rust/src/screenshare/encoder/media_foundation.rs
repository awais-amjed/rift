//! H264 on the GPU through Media Foundation's hardware encoders.
//!
//! A hardware encoder is an asynchronous transform: it says when it wants a
//! picture and when it has output, as events. It runs on a thread of its own,
//! which owns every COM object here, so nothing crosses threads but plain
//! bytes. Pictures come in on a short queue, newest kept; output goes straight
//! to the [`EncodedSink`].
use super::h264::{self, ParameterSets};
use super::{clamp_bitrate, Encoded, EncodedSink, EncoderSettings, Nv12Frame};
use std::mem::ManuallyDrop;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;
use windows::core::{Interface, GUID, PWSTR};
use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::{
    CoInitializeEx, CoTaskMemFree, CoUninitialize, COINIT_MULTITHREADED,
};
use windows::Win32::System::Variant::VARIANT;

/// Pictures waiting for the encoder. Two is one going in and one behind it;
/// anything older is stale and better dropped.
const FRAME_QUEUE: usize = 2;

/// How often the encoder thread looks for the transform's events while it has
/// nothing else to wait on.
const POLL: Duration = Duration::from_millis(1);

/// Frames between keyframes when nobody asks for one. WebRTC asks whenever a
/// viewer joins or loses packets, so this is only a safety net.
const GOP_SECONDS: u32 = 60;

/// Media Foundation's time unit is 100 ns.
const TICKS_PER_MICROSECOND: i64 = 10;

/// What a hardware encoder calls itself, for logs and for choosing.
#[derive(Clone, Debug)]
pub(crate) struct EncoderInfo {
    pub name: String,
    /// `VEN_10DE` NVIDIA, `VEN_8086` Intel, `VEN_1002` AMD.
    pub vendor: String,
}

/// COM and Media Foundation, started for this thread and stopped with it.
struct MediaFoundation {
    uninitialize_com: bool,
}

impl MediaFoundation {
    fn start() -> Result<Self, String> {
        // A thread that already chose another apartment keeps it; MF works
        // in either, and that thread's owner uninitialises it.
        let uninitialize_com = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }.is_ok();
        if let Err(e) = unsafe { MFStartup(MF_VERSION, MFSTARTUP_LITE) } {
            if uninitialize_com {
                unsafe { CoUninitialize() };
            }
            return Err(format!("Media Foundation did not start: {e}"));
        }
        Ok(Self { uninitialize_com })
    }
}

impl Drop for MediaFoundation {
    fn drop(&mut self) {
        unsafe {
            let _ = MFShutdown();
            if self.uninitialize_com {
                CoUninitialize();
            }
        }
    }
}

/// The hardware encoders that take NV12 and make H264, best first, as Media
/// Foundation sorts them.
fn h264_activates() -> Result<Vec<IMFActivate>, String> {
    let input = MFT_REGISTER_TYPE_INFO {
        guidMajorType: MFMediaType_Video,
        guidSubtype: MFVideoFormat_NV12,
    };
    let output = MFT_REGISTER_TYPE_INFO {
        guidMajorType: MFMediaType_Video,
        guidSubtype: MFVideoFormat_H264,
    };
    let mut found: *mut Option<IMFActivate> = std::ptr::null_mut();
    let mut count = 0u32;
    unsafe {
        MFTEnumEx(
            MFT_CATEGORY_VIDEO_ENCODER,
            MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER,
            Some(&input),
            Some(&output),
            &mut found,
            &mut count,
        )
        .map_err(|e| format!("listing the hardware encoders failed: {e}"))?;
        if found.is_null() {
            return Ok(Vec::new());
        }
        let activates = std::slice::from_raw_parts_mut(found, count as usize)
            .iter_mut()
            .filter_map(Option::take)
            .collect();
        CoTaskMemFree(Some(found as *const _));
        Ok(activates)
    }
}

fn string_attribute(activate: &IMFActivate, key: &GUID) -> String {
    let mut value = PWSTR::null();
    let mut length = 0u32;
    unsafe {
        if activate
            .GetAllocatedString(key, &mut value, &mut length)
            .is_err()
        {
            return String::new();
        }
        let text = value.to_string().unwrap_or_default();
        CoTaskMemFree(Some(value.0 as *const _));
        text
    }
}

fn info(activate: &IMFActivate) -> EncoderInfo {
    EncoderInfo {
        name: string_attribute(activate, &MFT_FRIENDLY_NAME_Attribute),
        vendor: string_attribute(activate, &MFT_ENUM_HARDWARE_VENDOR_ID_Attribute),
    }
}

/// The hardware H264 encoders on this machine, best first.
pub(crate) fn hardware_h264_encoders() -> Vec<EncoderInfo> {
    let _mf = match MediaFoundation::start() {
        Ok(mf) => mf,
        Err(reason) => {
            log::warn!("encoder: {reason}");
            return Vec::new();
        }
    };
    match h264_activates() {
        Ok(activates) => activates.iter().map(info).collect(),
        Err(reason) => {
            log::warn!("encoder: {reason}");
            Vec::new()
        }
    }
}

/// A running GPU encoder.
pub(crate) struct GpuEncoder {
    frames: Option<SyncSender<Nv12Frame>>,
    /// Picture buffers coming back from the encoder thread, to be filled again
    /// rather than allocated a frame at a time.
    spare: Arc<Mutex<Vec<Vec<u8>>>>,
    failed: Arc<AtomicBool>,
    handle: Option<JoinHandle<()>>,
    pub name: String,
}

impl GpuEncoder {
    /// Open the first hardware encoder that takes these settings, or the
    /// `only`th of [`hardware_h264_encoders`] when one is named, and start
    /// feeding `sink`.
    pub(crate) fn open(
        settings: EncoderSettings,
        sink: Box<dyn EncodedSink>,
        only: Option<usize>,
    ) -> Result<GpuEncoder, String> {
        let (frames_tx, frames_rx) = mpsc::sync_channel(FRAME_QUEUE);
        let (opened_tx, opened_rx) = mpsc::channel();
        let spare = Arc::new(Mutex::new(Vec::new()));
        let failed = Arc::new(AtomicBool::new(false));
        let thread_spare = spare.clone();
        let thread_failed = failed.clone();
        let handle = thread::Builder::new()
            .name("gpu-encoder".to_string())
            .spawn(move || {
                encoder_thread(
                    settings,
                    only,
                    sink,
                    frames_rx,
                    opened_tx,
                    thread_spare,
                    thread_failed,
                )
            })
            .map_err(|e| format!("no encoder thread: {e}"))?;
        match opened_rx.recv() {
            Ok(Ok(name)) => Ok(GpuEncoder {
                frames: Some(frames_tx),
                spare,
                failed,
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
    /// another one; this one will not recover.
    pub(crate) fn failed(&self) -> bool {
        self.failed.load(Ordering::Relaxed)
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

fn encoder_thread(
    settings: EncoderSettings,
    only: Option<usize>,
    mut sink: Box<dyn EncodedSink>,
    frames: Receiver<Nv12Frame>,
    opened: mpsc::Sender<Result<String, String>>,
    spare: Arc<Mutex<Vec<Vec<u8>>>>,
    failed: Arc<AtomicBool>,
) {
    let _mf = match MediaFoundation::start() {
        Ok(mf) => mf,
        Err(reason) => {
            let _ = opened.send(Err(reason));
            return;
        }
    };
    let mut transform = match open_transform(settings, only) {
        Ok(transform) => transform,
        Err(reason) => {
            let _ = opened.send(Err(reason));
            return;
        }
    };
    let _ = opened.send(Ok(transform.info.name.clone()));
    if let Err(e) = transform.run(&mut *sink, &frames, &spare) {
        log::warn!("encoder: {} stopped working: {e}", transform.info.name);
        failed.store(true, Ordering::Relaxed);
    }
    log::info!("encoder: {} closed", transform.info.name);
}

fn open_transform(settings: EncoderSettings, only: Option<usize>) -> Result<Transform, String> {
    let activates = h264_activates()?;
    if activates.is_empty() {
        return Err("This computer has no hardware H264 encoder".to_string());
    }
    let mut reasons = Vec::new();
    for (index, activate) in activates.into_iter().enumerate() {
        let info = info(&activate);
        if only.is_some_and(|only| only != index) {
            continue;
        }
        match Transform::open(activate.clone(), info.clone(), settings) {
            Ok(transform) => {
                log::info!(
                    "encoder: opened {} ({}) for {}x{} at {} fps, up to {} bps, {}",
                    info.name,
                    info.vendor,
                    settings.width,
                    settings.height,
                    settings.fps,
                    settings.max_bitrate_bps,
                    transform.profile
                );
                return Ok(transform);
            }
            Err(e) => {
                log::info!(
                    "encoder: {} ({}) would not open: {e}",
                    info.name,
                    info.vendor
                );
                unsafe {
                    let _ = activate.ShutdownObject();
                }
                reasons.push(format!("{}: {e}", info.name));
            }
        }
    }
    Err(format!(
        "No hardware H264 encoder opened ({})",
        reasons.join("; ")
    ))
}

/// An opened, configured, streaming hardware encoder.
struct Transform {
    activate: IMFActivate,
    transform: IMFTransform,
    events: IMFMediaEventGenerator,
    codec: ICodecAPI,
    info: EncoderInfo,
    settings: EncoderSettings,
    profile: &'static str,
    /// Whether the encoder hands out its own output samples, as hardware
    /// encoders usually do; otherwise one of this size is offered.
    provides_samples: bool,
    output_size: u32,
    bitrate: u32,
    parameter_sets: ParameterSets,
}

fn set_value(codec: &ICodecAPI, api: &GUID, value: VARIANT) -> windows::core::Result<()> {
    unsafe { codec.SetValue(api, &value) }
}

/// What the encoder says a setting is, for the log.
fn read_value(codec: &ICodecAPI, api: &GUID) -> String {
    match unsafe { codec.GetValue(api) } {
        Ok(value) => value.to_string(),
        Err(e) => format!("unknown ({e})"),
    }
}

/// A failed setup step, said with what it was.
fn step<T>(what: &str, result: windows::core::Result<T>) -> Result<T, String> {
    result.map_err(|e| format!("{what}: {e}"))
}

fn pack(high: u32, low: u32) -> u64 {
    (u64::from(high) << 32) | u64::from(low)
}

impl Transform {
    fn open(
        activate: IMFActivate,
        info: EncoderInfo,
        settings: EncoderSettings,
    ) -> Result<Transform, String> {
        unsafe {
            let transform: IMFTransform = step("activating", activate.ActivateObject())?;
            let attributes = step("reading its attributes", transform.GetAttributes())?;
            if attributes.GetUINT32(&MF_TRANSFORM_ASYNC).unwrap_or(0) == 0 {
                return Err("not an asynchronous encoder".to_string());
            }
            step(
                "unlocking it",
                attributes.SetUINT32(&MF_TRANSFORM_ASYNC_UNLOCK, 1),
            )?;
            let _ = attributes.SetUINT32(&MF_LOW_LATENCY, 1);
            let codec: ICodecAPI = step("its codec settings", transform.cast())?;

            // Rate control before the output type: some encoders fix it there.
            let optional = |api: &GUID, value: VARIANT, what: &str| {
                if let Err(e) = set_value(&codec, api, value) {
                    log::info!("encoder: {} would not take {what}: {e}", info.name);
                }
            };
            optional(
                &CODECAPI_AVEncCommonRateControlMode,
                VARIANT::from(eAVEncCommonRateControlMode_CBR.0 as u32),
                "constant bitrate",
            );
            optional(
                &CODECAPI_AVLowLatencyMode,
                VARIANT::from(true),
                "low latency",
            );
            // WebRTC cannot carry B-frames.
            step(
                "turning B-frames off",
                set_value(
                    &codec,
                    &CODECAPI_AVEncMPVDefaultBPictureCount,
                    VARIANT::from(0u32),
                ),
            )?;
            optional(
                &CODECAPI_AVEncMPVGOPSize,
                VARIANT::from(settings.fps * GOP_SECONDS),
                "a keyframe interval",
            );
            optional(
                &CODECAPI_AVEncCommonMeanBitRate,
                VARIANT::from(settings.max_bitrate_bps),
                "a bitrate",
            );

            let profile = step("the H264 output", set_output_type(&transform, settings))?;
            step("the NV12 input", set_input_type(&transform, settings))?;
            log::info!(
                "encoder: {} holds rate control {}, {} bps, low latency {}, GOP {}",
                info.name,
                read_value(&codec, &CODECAPI_AVEncCommonRateControlMode),
                read_value(&codec, &CODECAPI_AVEncCommonMeanBitRate),
                read_value(&codec, &CODECAPI_AVLowLatencyMode),
                read_value(&codec, &CODECAPI_AVEncMPVGOPSize),
            );

            let stream = step("its output stream", transform.GetOutputStreamInfo(0))?;
            let provides_samples = stream.dwFlags
                & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES.0 | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES.0)
                    as u32
                != 0;
            let output_size = stream
                .cbSize
                .max(Nv12Frame::len_for(settings.width, settings.height) as u32);

            step(
                "starting the stream",
                transform
                    .ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0)
                    .and_then(|()| transform.ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0))
                    .and_then(|()| transform.ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0)),
            )?;
            let events: IMFMediaEventGenerator = step("its events", transform.cast())?;
            Ok(Transform {
                activate,
                transform,
                events,
                codec,
                info,
                settings,
                profile,
                provides_samples,
                output_size,
                bitrate: settings.max_bitrate_bps,
                parameter_sets: ParameterSets::default(),
            })
        }
    }

    /// Feed pictures as the encoder asks for them and hand on what it makes,
    /// until the queue closes. An error is the encoder failing.
    fn run(
        &mut self,
        sink: &mut dyn EncodedSink,
        frames: &Receiver<Nv12Frame>,
        spare: &Mutex<Vec<Vec<u8>>>,
    ) -> windows::core::Result<()> {
        let mut wanted = 0u32;
        let mut pending: Option<Nv12Frame> = None;
        loop {
            loop {
                let event = match unsafe { self.events.GetEvent(MF_EVENT_FLAG_NO_WAIT) } {
                    Ok(event) => event,
                    Err(e) if e.code() == MF_E_NO_EVENTS_AVAILABLE => break,
                    Err(e) => return Err(e),
                };
                let kind = unsafe { event.GetType()? };
                if kind == METransformNeedInput.0 as u32 {
                    wanted += 1;
                } else if kind == METransformHaveOutput.0 as u32 {
                    self.take_output(sink)?;
                }
            }
            if wanted > 0 {
                if let Some(frame) = pending.take() {
                    self.apply_requests(sink);
                    let result = self.feed(&frame);
                    spare.lock().unwrap().push(frame.data);
                    result?;
                    wanted -= 1;
                    continue;
                }
            }
            match frames.recv_timeout(POLL) {
                Ok(frame) => {
                    if let Some(stale) = pending.replace(frame) {
                        spare.lock().unwrap().push(stale.data);
                    }
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return Ok(()),
            }
        }
    }

    /// Forward what WebRTC asked for since the last picture.
    fn apply_requests(&mut self, sink: &mut dyn EncodedSink) {
        if sink.keyframe_wanted() {
            if let Err(e) = set_value(
                &self.codec,
                &CODECAPI_AVEncVideoForceKeyFrame,
                VARIANT::from(1u32),
            ) {
                log::warn!("encoder: forcing a keyframe: {e}");
            }
        }
        if let Some(requested) = sink.bitrate_wanted() {
            let bitrate = clamp_bitrate(requested, self.settings.max_bitrate_bps);
            if bitrate != self.bitrate {
                match set_value(
                    &self.codec,
                    &CODECAPI_AVEncCommonMeanBitRate,
                    VARIANT::from(bitrate),
                ) {
                    Ok(()) => self.bitrate = bitrate,
                    Err(e) => log::warn!("encoder: setting {bitrate} bps: {e}"),
                }
            }
        }
    }

    fn feed(&self, frame: &Nv12Frame) -> windows::core::Result<()> {
        unsafe {
            let length = frame.data.len() as u32;
            let buffer = MFCreateMemoryBuffer(length)?;
            let mut bytes = std::ptr::null_mut();
            buffer.Lock(&mut bytes, None, None)?;
            std::ptr::copy_nonoverlapping(frame.data.as_ptr(), bytes, frame.data.len());
            buffer.Unlock()?;
            buffer.SetCurrentLength(length)?;
            let sample = MFCreateSample()?;
            sample.AddBuffer(&buffer)?;
            sample.SetSampleTime(frame.timestamp_us * TICKS_PER_MICROSECOND)?;
            sample.SetSampleDuration(10_000_000 / i64::from(self.settings.fps.max(1)))?;
            self.transform.ProcessInput(0, &sample, 0)
        }
    }

    fn take_output(&mut self, sink: &mut dyn EncodedSink) -> windows::core::Result<()> {
        unsafe {
            let offered = if self.provides_samples {
                None
            } else {
                let sample = MFCreateSample()?;
                sample.AddBuffer(&MFCreateMemoryBuffer(self.output_size)?)?;
                Some(sample)
            };
            let mut output = MFT_OUTPUT_DATA_BUFFER {
                dwStreamID: 0,
                pSample: ManuallyDrop::new(offered),
                dwStatus: 0,
                pEvents: ManuallyDrop::new(None),
            };
            let mut status = 0u32;
            let result =
                self.transform
                    .ProcessOutput(0, std::slice::from_mut(&mut output), &mut status);
            let sample = ManuallyDrop::take(&mut output.pSample);
            drop(ManuallyDrop::take(&mut output.pEvents));
            match result {
                Ok(()) => {}
                Err(e) if e.code() == MF_E_TRANSFORM_STREAM_CHANGE => {
                    log::info!("encoder: {} changed its output format", self.info.name);
                    let changed = self.transform.GetOutputAvailableType(0, 0)?;
                    return self.transform.SetOutputType(0, &changed, 0);
                }
                Err(e) if e.code() == MF_E_TRANSFORM_NEED_MORE_INPUT => return Ok(()),
                Err(e) => return Err(e),
            }
            let Some(sample) = sample else {
                return Ok(());
            };
            let buffer = sample.ConvertToContiguousBuffer()?;
            let mut bytes = std::ptr::null_mut();
            let mut length = 0u32;
            buffer.Lock(&mut bytes, None, Some(&mut length))?;
            let payload = std::slice::from_raw_parts(bytes, length as usize).to_vec();
            buffer.Unlock()?;
            if payload.is_empty() {
                return Ok(());
            }
            let clean_point = sample.GetUINT32(&MFSampleExtension_CleanPoint).unwrap_or(0) != 0;
            let keyframe = clean_point || h264::is_idr(&payload);
            let timestamp_us = sample.GetSampleTime()? / TICKS_PER_MICROSECOND;
            let payload = self.parameter_sets.complete(payload);
            sink.deliver(Encoded {
                payload: &payload,
                timestamp_us,
                keyframe,
            });
            Ok(())
        }
    }
}

impl Drop for Transform {
    fn drop(&mut self) {
        unsafe {
            let _ = self
                .transform
                .ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
            let _ = self
                .transform
                .ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
            if let Ok(shutdown) = self.transform.cast::<IMFShutdown>() {
                let _ = shutdown.Shutdown();
            }
            let _ = self.activate.ShutdownObject();
        }
    }
}

/// H264 out, in the profile WebRTC offers for a pre-encoded track
/// (constrained baseline, `42e01f`), or plain baseline from an encoder that
/// does not name the constrained one: a hardware encoder uses none of the
/// tools that separate them.
unsafe fn set_output_type(
    transform: &IMFTransform,
    settings: EncoderSettings,
) -> windows::core::Result<&'static str> {
    let mut last = None;
    for (profile, name) in [
        (eAVEncH264VProfile_ConstrainedBase, "constrained baseline"),
        (eAVEncH264VProfile_Base, "baseline"),
    ] {
        let media = MFCreateMediaType()?;
        media.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
        media.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_H264)?;
        media.SetUINT32(&MF_MT_AVG_BITRATE, settings.max_bitrate_bps)?;
        media.SetUINT64(&MF_MT_FRAME_SIZE, pack(settings.width, settings.height))?;
        media.SetUINT64(&MF_MT_FRAME_RATE, pack(settings.fps, 1))?;
        media.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, pack(1, 1))?;
        media.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
        media.SetUINT32(&MF_MT_MPEG2_PROFILE, profile.0 as u32)?;
        match transform.SetOutputType(0, &media, 0) {
            Ok(()) => return Ok(name),
            Err(e) => last = Some(e),
        }
    }
    Err(last.expect("tried at least one profile"))
}

unsafe fn set_input_type(
    transform: &IMFTransform,
    settings: EncoderSettings,
) -> windows::core::Result<()> {
    let media = MFCreateMediaType()?;
    media.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
    media.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_NV12)?;
    media.SetUINT64(&MF_MT_FRAME_SIZE, pack(settings.width, settings.height))?;
    media.SetUINT64(&MF_MT_FRAME_RATE, pack(settings.fps, 1))?;
    media.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, pack(1, 1))?;
    media.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
    media.SetUINT32(&MF_MT_DEFAULT_STRIDE, settings.width)?;
    transform.SetInputType(0, &media, 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    /// Keeps what the encoder made, and asks for one keyframe on cue.
    struct Recorder {
        frames: Arc<Mutex<Vec<(Vec<u8>, bool)>>>,
        want_keyframe: Arc<AtomicBool>,
    }

    impl EncodedSink for Recorder {
        fn deliver(&mut self, frame: Encoded<'_>) {
            self.frames
                .lock()
                .unwrap()
                .push((frame.payload.to_vec(), frame.keyframe));
        }
        fn keyframe_wanted(&mut self) -> bool {
            self.want_keyframe.swap(false, Ordering::Relaxed)
        }
        fn bitrate_wanted(&mut self) -> Option<u64> {
            None
        }
    }

    /// A moving picture: a gradient sliding a few pixels a frame, so every
    /// frame differs and none is trivially small. Far from real content:
    /// Intel's rate control cannot hold it to the target (Oct 4 2026), so
    /// the bitrate is judged on real frames from `GPU_ENCODER_SOURCE`.
    fn picture(width: u32, height: u32, n: u32, into: &mut [u8]) {
        let (w, h) = (width as usize, height as usize);
        for y in 0..h {
            for x in 0..w {
                into[y * w + x] = ((x + y + n as usize * 4) % 256) as u8;
            }
        }
        for (i, byte) in into[w * h..].iter_mut().enumerate() {
            *byte = ((i / 2 + n as usize * 2) % 256) as u8;
        }
    }

    #[test]
    #[ignore = "needs a hardware H264 encoder"]
    fn each_hardware_encoder_makes_decodable_h264() {
        let _ = env_logger::builder()
            .is_test(true)
            .filter_level(log::LevelFilter::Info)
            .try_init();
        let encoders = hardware_h264_encoders();
        log::info!("hardware H264 encoders: {encoders:?}");
        assert!(!encoders.is_empty(), "no hardware H264 encoder here");
        let settings = EncoderSettings {
            width: 1920,
            height: 1080,
            fps: 60,
            max_bitrate_bps: 8_000_000,
        };
        let mut worked = 0;
        for (index, encoder) in encoders.iter().enumerate() {
            let frames = Arc::new(Mutex::new(Vec::new()));
            let want_keyframe = Arc::new(AtomicBool::new(false));
            let opened = GpuEncoder::open(
                settings,
                Box::new(Recorder {
                    frames: frames.clone(),
                    want_keyframe: want_keyframe.clone(),
                }),
                Some(index),
            );
            // On a laptop with two GPUs, NVIDIA's encoder only activates in a
            // process Windows runs on the NVIDIA one (verified Oct 4 2026,
            // ffmpeg's h264_mf the same); the next encoder is the answer then.
            let gpu = match opened {
                Ok(gpu) => gpu,
                Err(e) if e.contains("activating") => {
                    log::info!("{}: skipped, {e}", encoder.name);
                    continue;
                }
                Err(e) => panic!("{}: {e}", encoder.name),
            };
            let started = Instant::now();
            let source = std::env::var("GPU_ENCODER_SOURCE")
                .ok()
                .map(|path| std::fs::read(path).unwrap());
            for n in 0..180u32 {
                let len = Nv12Frame::len_for(settings.width, settings.height);
                let mut data = gpu.buffer(len);
                match &source {
                    // Raw NV12 frames at the test's size, e.g. from
                    // `ffmpeg -i clip.mp4 -pix_fmt nv12 -f rawvideo`.
                    Some(raw) => {
                        let at = (n as usize * len) % raw.len();
                        data.copy_from_slice(&raw[at..at + len]);
                    }
                    None => picture(settings.width, settings.height, n, &mut data),
                }
                if n == 90 {
                    want_keyframe.store(true, Ordering::Relaxed);
                }
                gpu.submit(Nv12Frame {
                    data,
                    timestamp_us: i64::from(n) * 16_667,
                });
                std::thread::sleep(Duration::from_micros(16_667));
            }
            std::thread::sleep(Duration::from_millis(200));
            let failed = gpu.failed();
            drop(gpu);
            let frames = frames.lock().unwrap();
            let keyframes: Vec<usize> = frames
                .iter()
                .enumerate()
                .filter(|(_, (_, key))| *key)
                .map(|(i, _)| i)
                .collect();
            let bytes: usize = frames.iter().map(|(p, _)| p.len()).sum();
            log::info!(
                "{}: {} frames in {:.2} s, {} bytes, keyframes at {keyframes:?}",
                encoder.name,
                frames.len(),
                started.elapsed().as_secs_f64(),
                bytes
            );
            assert!(!failed, "{} failed", encoder.name);
            assert!(
                frames.len() >= 150,
                "{}: {} frames",
                encoder.name,
                frames.len()
            );
            assert_eq!(
                keyframes.first(),
                Some(&0),
                "{} starts on a keyframe",
                encoder.name
            );
            assert!(
                keyframes.len() >= 2,
                "{} made the keyframe asked for",
                encoder.name
            );
            let first = &frames[0].0;
            let kinds: Vec<u8> = h264::nal_units(first).iter().map(|&(k, _)| k).collect();
            assert!(
                kinds.contains(&7) && kinds.contains(&8),
                "{}: first frame has SPS and PPS: {kinds:?}",
                encoder.name
            );
            for &k in &keyframes {
                let kinds: Vec<u8> = h264::nal_units(&frames[k].0)
                    .iter()
                    .map(|&(k, _)| k)
                    .collect();
                assert!(kinds.contains(&7), "keyframe {k} carries an SPS: {kinds:?}");
            }
            if let Ok(dir) = std::env::var("GPU_ENCODER_DUMP") {
                let stream: Vec<u8> = frames.iter().flat_map(|(p, _)| p.iter().copied()).collect();
                let path = format!("{dir}/gpu-{index}.h264");
                std::fs::write(&path, stream).unwrap();
                log::info!("wrote {path}");
            }
            worked += 1;
        }
        assert!(worked > 0, "no hardware encoder worked");
    }
}
