//! Linux: record one application's stream through the monitor of the sink
//! it plays to.
use super::pulse::{self, Connection};
use super::{samples_from_le_bytes, AudioCaptureHandle, Command, NUM_CHANNELS, SAMPLE_RATE};
use crate::api::screenshare::types::ScreenShareConfig;
use libpulse_binding as pa;
use livekit::prelude::*;
use pa::def::BufferAttr;
use pa::sample::{Format, Spec};
use pa::stream::{FlagSet, PeekResult, State, Stream};
use std::sync::mpsc::{Receiver, TryRecvError};
use std::thread::{self, JoinHandle};
use tokio::sync::mpsc::Sender as FrameSender;

/// Ten milliseconds of audio, the size LiveKit likes its frames in.
const FRAME_BYTES: usize = (SAMPLE_RATE as usize / 100) * NUM_CHANNELS as usize * 2;

pub(crate) async fn start(room: &Room, config: &ScreenShareConfig) -> Option<AudioCaptureHandle> {
    let (Some(sink_input), Some(sink)) = (
        config.selected_audio_source_index,
        config.selected_audio_source_sink,
    ) else {
        log::info!("audio: sharing enabled but no application selected");
        return None;
    };
    let Some(monitor) = pulse::monitor_source_name(sink) else {
        log::warn!("audio: sink #{sink} has no monitor source");
        return None;
    };
    log::info!("audio: capturing sink-input #{sink_input} via {monitor}");
    super::publish_and_feed(
        room,
        Box::new(move |commands, frames| {
            spawn_capture_thread(sink_input, monitor, commands, frames)
        }),
    )
    .await
}

fn spawn_capture_thread(
    sink_input: u32,
    monitor: String,
    commands: Receiver<Command>,
    frames: FrameSender<Vec<i16>>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let Some(mut connection) = Connection::open("rift-screenshare-audio") else {
            return;
        };
        let Some(mut stream) = open_stream(&mut connection, sink_input, &monitor) else {
            return;
        };
        log::info!("audio: recording from {monitor}");
        let mut pending: Vec<u8> = Vec::with_capacity(FRAME_BYTES * 2);
        loop {
            match commands.try_recv() {
                Ok(Command::Terminate) | Err(TryRecvError::Disconnected) => break,
                Err(TryRecvError::Empty) => {}
            }
            if !connection.turn() {
                log::warn!("audio: PulseAudio mainloop failed");
                break;
            }
            match stream.peek() {
                Ok(PeekResult::Data(data)) => {
                    pending.extend_from_slice(data);
                    let _ = stream.discard();
                    while pending.len() >= FRAME_BYTES {
                        let frame: Vec<u8> = pending.drain(..FRAME_BYTES).collect();
                        if frames.blocking_send(samples_from_le_bytes(&frame)).is_err() {
                            return;
                        }
                    }
                }
                Ok(PeekResult::Hole(_)) => {
                    let _ = stream.discard();
                }
                Ok(PeekResult::Empty) => {}
                Err(e) => {
                    log::warn!("audio: PulseAudio read failed: {e:?}");
                    break;
                }
            }
        }
        let _ = stream.disconnect();
        log::info!("audio: capture thread exiting");
    })
}

/// A record stream on `monitor`, restricted to one sink-input, ready to read.
fn open_stream(connection: &mut Connection, sink_input: u32, monitor: &str) -> Option<Stream> {
    let spec = Spec {
        format: Format::S16le,
        channels: NUM_CHANNELS as u8,
        rate: SAMPLE_RATE,
    };
    let mut stream = Stream::new(&mut connection.context, "screenshare-audio", &spec, None)?;
    if stream.set_monitor_stream(sink_input).is_err() {
        log::warn!("audio: sink-input #{sink_input} cannot be monitored");
        return None;
    }
    let attr = BufferAttr {
        maxlength: u32::MAX,
        tlength: u32::MAX,
        prebuf: u32::MAX,
        minreq: u32::MAX,
        fragsize: FRAME_BYTES as u32,
    };
    if stream
        .connect_record(Some(monitor), Some(&attr), FlagSet::ADJUST_LATENCY)
        .is_err()
    {
        log::warn!("audio: could not open a record stream on {monitor}");
        return None;
    }
    loop {
        if !connection.turn() {
            return None;
        }
        match stream.get_state() {
            State::Ready => return Some(stream),
            State::Failed | State::Terminated => {
                log::warn!("audio: record stream failed to start");
                return None;
            }
            _ => {}
        }
    }
}
