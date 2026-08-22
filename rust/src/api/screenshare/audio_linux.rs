//! Linux audio enumeration and capture for screenshare
//!
//! This module provides PulseAudio-based audio capture functionality.

#[cfg(target_os = "linux")]
use libpulse_binding as pulse;

#[cfg(target_os = "linux")]
use pulse::context::Context;
#[cfg(target_os = "linux")]
use pulse::def::BufferAttr;
#[cfg(target_os = "linux")]
use pulse::mainloop::standard::Mainloop;
#[cfg(target_os = "linux")]
use pulse::sample::{Format, Spec};
#[cfg(target_os = "linux")]
use pulse::stream::{FlagSet as StreamFlagSet, PeekResult, Stream};

#[cfg(target_os = "linux")]
use livekit::options::TrackPublishOptions;
// Only for `Room`, which comes from a crate this build has
// only on the desktop — see Cargo.toml.
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use livekit::prelude::*;
#[cfg(target_os = "linux")]
use livekit::track::{LocalAudioTrack, LocalTrack, TrackSource};
#[cfg(target_os = "linux")]
use livekit::webrtc::audio_frame::AudioFrame;
#[cfg(target_os = "linux")]
use livekit::webrtc::audio_source::native::NativeAudioSource;
#[cfg(target_os = "linux")]
use livekit::webrtc::audio_source::{AudioSourceOptions, RtcAudioSource};

use std::sync::mpsc::Sender;
#[cfg(target_os = "linux")]
use std::sync::mpsc::{self, Receiver};
#[cfg(target_os = "linux")]
use std::sync::{Arc, Mutex};
#[cfg(target_os = "linux")]
use std::thread;
use std::thread::JoinHandle;
#[cfg(target_os = "linux")]
use tokio::sync::mpsc::Sender as TokioFrameSender;
use tokio::task::JoinHandle as TokioJoinHandle;

#[allow(dead_code)]
const SAMPLE_RATE: u32 = 48000;
#[allow(dead_code)]
const NUM_CHANNELS: u32 = 2;
#[allow(dead_code)]
const FRAME_SIZE_BYTES: usize = (SAMPLE_RATE as usize / 100) * NUM_CHANNELS as usize * 2;

/// Represents an audio source that can be captured
#[derive(Clone, Debug)]
pub struct AudioSource {
    pub index: u32,
    pub sink: u32,
    pub app_name: String,
    pub binary: String,
    pub media_name: String,
}

pub enum AudioCaptureCommand {
    Terminate,
}

/// Handle for managing audio capture lifecycle
#[flutter_rust_bridge::frb(ignore)]
pub struct AudioCaptureHandle {
    command_tx: Sender<AudioCaptureCommand>,
    capture_thread: JoinHandle<()>,
    feed_task: TokioJoinHandle<()>,
}

impl AudioCaptureHandle {
    /// Gracefully terminate audio capture
    pub fn terminate(self) {
        let _ = self.command_tx.send(AudioCaptureCommand::Terminate);
        self.feed_task.abort();
        if let Err(err) = self.capture_thread.join() {
            println!("Audio capture thread join error: {:?}", err);
        }
    }
}

/// List all active PulseAudio sink-inputs (audio sources).
#[cfg(target_os = "linux")]
pub fn list_audio_sources() -> Vec<AudioSource> {
    let mut mainloop = match Mainloop::new() {
        Some(ml) => ml,
        None => {
            println!("Failed to create PulseAudio mainloop");
            return Vec::new();
        }
    };

    let mut context = match Context::new(&mainloop, "rift-audio-list") {
        Some(ctx) => ctx,
        None => {
            println!("Failed to create PA context");
            return Vec::new();
        }
    };

    if context
        .connect(None, pulse::context::FlagSet::NOFLAGS, None)
        .is_err()
    {
        println!("Failed to connect to PA");
        return Vec::new();
    }

    loop {
        mainloop.iterate(true);
        match context.get_state() {
            pulse::context::State::Ready => break,
            pulse::context::State::Failed | pulse::context::State::Terminated => {
                println!("PulseAudio context failed to connect");
                return Vec::new();
            }
            _ => {}
        }
    }

    let entries: Arc<Mutex<Vec<AudioSource>>> = Arc::new(Mutex::new(Vec::new()));
    let entries_clone = entries.clone();
    let done = Arc::new(Mutex::new(false));
    let done_clone = done.clone();

    let introspect = context.introspect();
    let _op = introspect.get_sink_input_info_list(move |list_result| match list_result {
        pulse::callbacks::ListResult::Item(info) => {
            let entry = AudioSource {
                index: info.index,
                sink: info.sink,
                app_name: info
                    .proplist
                    .get_str("application.name")
                    .unwrap_or_default(),
                binary: info
                    .proplist
                    .get_str("application.process.binary")
                    .unwrap_or_default(),
                media_name: info.proplist.get_str("media.name").unwrap_or_default(),
            };
            entries_clone.lock().unwrap().push(entry);
        }
        pulse::callbacks::ListResult::End => {
            *done_clone.lock().unwrap() = true;
        }
        pulse::callbacks::ListResult::Error => {
            *done_clone.lock().unwrap() = true;
        }
    });

    loop {
        mainloop.iterate(true);
        if *done.lock().unwrap() {
            break;
        }
        // Guard against PA crashing after the introspection request was dispatched
        // but before the callback fires — without this the loop would spin forever.
        match context.get_state() {
            pulse::context::State::Failed | pulse::context::State::Terminated => {
                println!("PulseAudio context failed while waiting for sink-input list");
                break;
            }
            _ => {}
        }
    }

    context.disconnect();
    mainloop.quit(pulse::def::Retval(0));

    let result = entries.lock().unwrap().clone();
    result
}

#[cfg(not(target_os = "linux"))]
pub fn list_audio_sources() -> Vec<AudioSource> {
    Vec::new()
}

/// Get the monitor source name for a given sink index.
#[cfg(target_os = "linux")]
fn get_monitor_source_name(sink_index: u32) -> Option<String> {
    let mut mainloop = Mainloop::new().expect("Failed to create PulseAudio mainloop");
    let mut context =
        Context::new(&mainloop, "rift-audio-monitor").expect("Failed to create PA context");

    context
        .connect(None, pulse::context::FlagSet::NOFLAGS, None)
        .expect("Failed to connect to PA");

    loop {
        mainloop.iterate(true);
        match context.get_state() {
            pulse::context::State::Ready => break,
            pulse::context::State::Failed | pulse::context::State::Terminated => {
                println!("PulseAudio context failed");
                return None;
            }
            _ => {}
        }
    }

    let result: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    let result_clone = result.clone();
    let done = Arc::new(Mutex::new(false));
    let done_clone = done.clone();

    let introspect = context.introspect();
    let _op = introspect.get_sink_info_by_index(sink_index, move |list_result| match list_result {
        pulse::callbacks::ListResult::Item(info) => {
            if let Some(monitor_source_name) = &info.monitor_source_name {
                let mut r = result_clone.lock().unwrap();
                *r = Some(monitor_source_name.to_string());
            }
        }
        pulse::callbacks::ListResult::End => {
            *done_clone.lock().unwrap() = true;
        }
        pulse::callbacks::ListResult::Error => {
            println!("Error getting sink info");
            *done_clone.lock().unwrap() = true;
        }
    });

    loop {
        mainloop.iterate(true);
        if *done.lock().unwrap() {
            break;
        }
        // Guard against PA crashing after the introspection request was dispatched
        // but before the callback fires — without this the loop would spin forever.
        match context.get_state() {
            pulse::context::State::Failed | pulse::context::State::Terminated => {
                println!("PulseAudio context failed while waiting for sink info");
                break;
            }
            _ => {}
        }
    }

    context.disconnect();
    mainloop.quit(pulse::def::Retval(0));

    let guard = result.lock().unwrap();
    guard.clone()
}

/// Spawn a thread that captures audio from a specific PulseAudio sink-input
#[cfg(target_os = "linux")]
fn spawn_audio_capture_thread(
    sink_input_index: u32,
    monitor_source_name: &str,
    command_rx: Receiver<AudioCaptureCommand>,
    frame_tx: TokioFrameSender<Vec<i16>>,
) -> JoinHandle<()> {
    let monitor_source = monitor_source_name.to_string();

    let handle = thread::spawn(move || {
        let mut mainloop = Mainloop::new().expect("Failed to create PA mainloop for audio capture");
        let mut context = Context::new(&mainloop, "rift-screenshare-audio-capture")
            .expect("Failed to create PA context");

        context
            .connect(None, pulse::context::FlagSet::NOFLAGS, None)
            .expect("Failed to connect to PA");

        loop {
            mainloop.iterate(true);
            match context.get_state() {
                pulse::context::State::Ready => break,
                pulse::context::State::Failed | pulse::context::State::Terminated => {
                    println!("PA context failed during audio capture setup");
                    return;
                }
                _ => {}
            }
        }

        let spec = Spec {
            format: Format::S16le,
            channels: NUM_CHANNELS as u8,
            rate: SAMPLE_RATE,
        };
        assert!(spec.is_valid());

        let mut stream = Stream::new(&mut context, "screenshare-audio", &spec, None)
            .expect("Failed to create PA stream");

        stream
            .set_monitor_stream(sink_input_index)
            .expect("Failed to set monitor stream for sink-input");

        let buf_attr = BufferAttr {
            maxlength: u32::MAX,
            tlength: u32::MAX,
            prebuf: u32::MAX,
            minreq: u32::MAX,
            fragsize: FRAME_SIZE_BYTES as u32,
        };

        stream
            .connect_record(
                Some(&monitor_source),
                Some(&buf_attr),
                StreamFlagSet::ADJUST_LATENCY,
            )
            .expect("Failed to connect PA record stream");

        loop {
            mainloop.iterate(true);
            match stream.get_state() {
                pulse::stream::State::Ready => break,
                pulse::stream::State::Failed | pulse::stream::State::Terminated => {
                    println!("PA stream failed to become ready");
                    return;
                }
                _ => {}
            }
        }

        println!(
            "Audio capture started: monitor_source='{}', sink_input=#{}",
            monitor_source, sink_input_index
        );

        let mut accumulator: Vec<u8> = Vec::with_capacity(FRAME_SIZE_BYTES * 2);

        loop {
            match command_rx.try_recv() {
                Ok(AudioCaptureCommand::Terminate) => {
                    println!("Audio capture thread received terminate");
                    break;
                }
                Err(mpsc::TryRecvError::Disconnected) => break,
                Err(mpsc::TryRecvError::Empty) => {}
            }

            mainloop.iterate(false);

            if let Some(readable) = stream.readable_size() {
                if readable == 0 {
                    mainloop.iterate(true);
                    continue;
                }
            }

            match stream.peek() {
                Ok(PeekResult::Data(data)) => {
                    accumulator.extend_from_slice(data);
                    stream.discard().ok();

                    while accumulator.len() >= FRAME_SIZE_BYTES {
                        let frame_bytes: Vec<u8> = accumulator.drain(..FRAME_SIZE_BYTES).collect();
                        let samples: Vec<i16> = frame_bytes
                            .chunks_exact(2)
                            .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
                            .collect();

                        if frame_tx.blocking_send(samples).is_err() {
                            println!("Audio frame receiver dropped, stopping capture");
                            return;
                        }
                    }
                }
                Ok(PeekResult::Hole(_)) => {
                    stream.discard().ok();
                }
                Ok(PeekResult::Empty) => {
                    mainloop.iterate(true);
                }
                Err(e) => {
                    println!("PA stream peek error: {:?}", e);
                    break;
                }
            }
        }

        stream.disconnect().ok();
        context.disconnect();
        println!("Audio capture thread exiting");
    });

    handle
}

/// Start audio capture for the given audio source
#[flutter_rust_bridge::frb(ignore)]
#[cfg(target_os = "linux")]
pub async fn start_audio_capture(
    room: &Room,
    sink_input_idx: u32,
    sink_idx: u32,
) -> Option<AudioCaptureHandle> {
    let monitor_source = get_monitor_source_name(sink_idx)?;
    println!(
        "Audio capture: sink-input #{}, sink #{}, monitor='{}'",
        sink_input_idx, sink_idx, monitor_source
    );

    let audio_source = NativeAudioSource::new(
        AudioSourceOptions::default(),
        SAMPLE_RATE,
        NUM_CHANNELS,
        100,
    );

    let audio_track = LocalAudioTrack::create_audio_track(
        "screen_share_audio",
        RtcAudioSource::Native(audio_source.clone()),
    );

    room.local_participant()
        .publish_track(
            LocalTrack::Audio(audio_track),
            TrackPublishOptions {
                source: TrackSource::ScreenshareAudio,
                ..Default::default()
            },
        )
        .await
        .ok()?;

    println!("Audio track published to LiveKit");

    let (audio_cmd_tx, audio_cmd_rx) = mpsc::channel();
    let (async_tx, mut async_rx) = tokio::sync::mpsc::channel::<Vec<i16>>(100);
    let audio_thread_handle =
        spawn_audio_capture_thread(sink_input_idx, &monitor_source, audio_cmd_rx, async_tx);

    // LiveKit sender task
    let audio_feed_task = tokio::spawn(async move {
        let samples_per_channel = SAMPLE_RATE / 100;
        while let Some(samples) = async_rx.recv().await {
            let frame = AudioFrame {
                data: samples.as_slice().into(),
                sample_rate: SAMPLE_RATE,
                num_channels: NUM_CHANNELS,
                samples_per_channel,
            };
            if let Err(e) = audio_source.capture_frame(&frame).await {
                println!("Failed to capture audio frame: {}", e);
            }
        }
    });

    Some(AudioCaptureHandle {
        command_tx: audio_cmd_tx,
        capture_thread: audio_thread_handle,
        feed_task: audio_feed_task,
    })
}

#[flutter_rust_bridge::frb(ignore)]
#[cfg(all(any(target_os = "windows", target_os = "linux", target_os = "macos"), not(target_os = "linux")))]
pub async fn start_audio_capture(
    _room: &Room,
    _sink_input_idx: u32,
    _sink_idx: u32,
) -> Option<AudioCaptureHandle> {
    None
}
