//! Linux: record one application's stream through the monitor of the sink
//! it plays to. With none picked, every application's but Rift's
//! (`linux_all`).
use super::linux_all;
use super::pulse;
use super::{
    samples_from_le_bytes, AudioCapture, AudioCaptureHandle, Command, Pcm, NUM_CHANNELS,
    SAMPLE_RATE,
};
use crate::pulse::Connection;
use libpulse_binding as pa;
use livekit::prelude::*;
use pa::context::subscribe::{Facility, InterestMaskSet, Operation};
use pa::def::BufferAttr;
use pa::sample::{Format, Spec};
use pa::stream::{FlagSet, PeekResult, State, Stream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, TryRecvError};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use tokio::sync::mpsc::Sender as FrameSender;

/// Ten milliseconds of audio, the size LiveKit likes its frames in.
const FRAME_BYTES: usize = (SAMPLE_RATE as usize / 100) * NUM_CHANNELS as usize * 2;

pub(crate) async fn start(room: &Room, request: AudioCapture) -> Option<AudioCaptureHandle> {
    let (Some(sink_input), Some(sink)) = (request.selection.sink_input, request.selection.sink)
    else {
        return super::publish_and_feed(
            room,
            Box::new(linux_all::spawn_capture_thread),
            &request.track_name,
            request.on_ended,
        )
        .await;
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
        &request.track_name,
        request.on_ended,
    )
    .await
}

fn spawn_capture_thread(
    sink_input: u32,
    monitor: String,
    commands: Receiver<Command>,
    frames: FrameSender<Pcm>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let Some(mut connection) = Connection::open("rift-screenshare-audio") else {
            return;
        };
        let Some(mut stream) = open_stream(&mut connection, sink_input, &monitor) else {
            return;
        };
        let removed = watch_for_removal(&mut connection, sink_input);
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
            // The application whose stream this follows can quit, and a
            // monitor of a sink-input that no longer exists is not an error,
            // only a stream that is no longer ready. A sound share reports
            // that upwards and ends; a screen share carries on in silence.
            if !matches!(stream.get_state(), State::Ready) {
                log::info!("audio: the record stream is no longer ready");
                break;
            }
            // PipeWire keeps the stream ready instead: see `watch_for_removal`.
            if removed.load(Ordering::SeqCst) {
                log::info!("audio: the application's stream ended");
                break;
            }
            match stream.peek() {
                Ok(PeekResult::Data(data)) => {
                    pending.extend_from_slice(data);
                    let _ = stream.discard();
                    while pending.len() >= FRAME_BYTES {
                        let frame: Vec<u8> = pending.drain(..FRAME_BYTES).collect();
                        if frames
                            .blocking_send(Pcm::read_now(samples_from_le_bytes(&frame)))
                            .is_err()
                        {
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

/// Set once `sink_input` goes away.
///
/// PulseAudio ends a monitor of a sink-input that is gone. PipeWire does not:
/// it links the record stream to the default output's monitor instead, and
/// the stream stays ready, so a share of one application went on with
/// everything the desktop played once that application stopped its stream —
/// seen Oct 12 2026 on PipeWire 1.4 with WirePlumber. `DONT_MOVE` stops the
/// relinking (pipewire-pulse makes it `node.dont-reconnect`), and this ends
/// the capture the way a stream that is no longer ready does.
fn watch_for_removal(connection: &mut Connection, sink_input: u32) -> Arc<AtomicBool> {
    let removed = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&removed);
    connection
        .context
        .set_subscribe_callback(Some(Box::new(move |facility, operation, index| {
            if facility == Some(Facility::SinkInput)
                && operation == Some(Operation::Removed)
                && index == sink_input
            {
                flag.store(true, Ordering::SeqCst);
            }
        })));
    let _ = connection
        .context
        .subscribe(InterestMaskSet::SINK_INPUT, |_| {});
    removed
}

/// A record stream on `monitor`, restricted to one sink-input, ready to read.
fn open_stream(connection: &mut Connection, sink_input: u32, monitor: &str) -> Option<Stream> {
    let stream = connect_stream(connection, sink_input, monitor)?;
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

/// The same, asked for and not waited on: it is ready some turns later.
pub(super) fn connect_stream(
    connection: &mut Connection,
    sink_input: u32,
    monitor: &str,
) -> Option<Stream> {
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
        .connect_record(
            Some(monitor),
            Some(&attr),
            // Never moved elsewhere: see `watch_for_removal`.
            FlagSet::ADJUST_LATENCY | FlagSet::DONT_MOVE,
        )
        .is_err()
    {
        log::warn!("audio: could not open a record stream on {monitor}");
        return None;
    }
    Some(stream)
}
