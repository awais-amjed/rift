//! Linux: a stereo playback stream on the chosen sink, through PulseAudio (or
//! PipeWire's PulseAudio server), the way the mic test plays you back.

use super::drift::Drift;
use super::{output_changes, playable, Gain, CHANNELS, SAMPLE_RATE};
use crate::cue::le_bytes;
use crate::pulse::{self, Connection};
use libpulse_binding as pa;
use pa::def::BufferAttr;
use pa::mainloop::standard::IterateResult;
use pa::sample::{Format, Spec};
use pa::stream::{FlagSet, SeekMode, State, Stream};
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::Duration;

pub(crate) const PLAYS: bool = true;

/// How much the output is asked to hold ahead of what is heard, in samples:
/// 60 ms, as the mic test's playback asks. PipeWire keeps it to less (see
/// [`CUSHION_SAMPLES`]). Each millisecond held is one the sound trails its
/// picture by, since libwebrtc times the picture to the sound as it leaves the
/// connection, not as it reaches the ear.
const HELD_SAMPLES: usize = (SAMPLE_RATE * CHANNELS) as usize * 60 / 1000;

/// How far past [`HELD_SAMPLES`] a frame may be written: one 10 ms frame, and
/// the pair [`Drift`] may add to it. The
/// server frees room a block of its own at a time, which is rarely one
/// frame, and cut to the room nearly every frame lost its tail (the mic
/// test's crackle, Oct 14).
const SLACK_SAMPLES: usize = (SAMPLE_RATE * CHANNELS) as usize / 100 + CHANNELS as usize;

/// Silence put ahead of the sound when a stream opens: 15 ms. PipeWire took a
/// stream asking to hold 60 ms down to holding about 20, about 6 ms from
/// running dry (Nov 5, a null sink), too little to steer by.
const CUSHION_SAMPLES: usize = (SAMPLE_RATE * CHANNELS) as usize * 15 / 1000;

/// How long to wait for a frame before turning the server's side over
/// anyway: two frames' time.
const WAIT: Duration = Duration::from_millis(20);

pub(super) fn run(frames: Receiver<Vec<i16>>, gain: &Gain) -> Result<(), String> {
    let mut connection =
        Connection::open("rift-watch").ok_or("could not reach the sound server")?;
    let mut output: Option<Output> = None;
    let ended = play_until_fed(&frames, gain, &mut connection, &mut output);
    if let Some(mut output) = output {
        let _ = output.stream.disconnect();
    }
    ended
}

/// A playback stream, and the output change it was opened for.
struct Output {
    change: u64,
    stream: Stream,
    drift: Drift,
    /// What the server keeps the stream topped up to, in samples: its own
    /// figure, as it may not be what was asked for.
    target_length: usize,
    /// No sound has gone in yet.
    fresh: bool,
}

/// Plays each frame until the feed ends (Ok) or the output fails.
fn play_until_fed(
    frames: &Receiver<Vec<i16>>,
    gain: &Gain,
    connection: &mut Connection,
    output: &mut Option<Output>,
) -> Result<(), String> {
    loop {
        let frame = match frames.recv_timeout(WAIT) {
            Ok(frame) => Some(frame),
            Err(RecvTimeoutError::Timeout) => None,
            Err(RecvTimeoutError::Disconnected) => return Ok(()),
        };
        if !turn_over(connection) {
            return Err("the sound server went away".to_string());
        }
        if output.as_ref().map(|output| output.change) != Some(output_changes()) {
            if let Some(mut old) = output.take() {
                let _ = old.stream.disconnect();
            }
            let (change, device) = super::output();
            let mut stream = open(connection, device.as_deref())?;
            let target_length = stream
                .get_buffer_attr()
                .map_or(HELD_SAMPLES, |attr| attr.tlength as usize / 2);
            *output = Some(Output {
                change,
                stream,
                drift: Drift::new(target_length),
                target_length,
                fresh: true,
            });
        }
        let (Some(frame), Some(output)) = (frame, output.as_mut()) else {
            continue;
        };
        let writable = output.stream.writable_size().unwrap_or(0) / 2;
        let queued = output.target_length.saturating_sub(writable);
        let frame = output.drift.adjust(&frame, queued);
        let room = writable + SLACK_SAMPLES;
        let mut played = if output.fresh {
            output.fresh = false;
            vec![0; CUSHION_SAMPLES]
        } else {
            Vec::new()
        };
        played.extend(playable(&frame, room, gain.get()));
        if played.is_empty() {
            continue;
        }
        output
            .stream
            .write(&le_bytes(&played), None, 0, SeekMode::Relative)
            .map_err(|e| format!("playing the sound failed: {e:?}"))?;
    }
}

/// Everything the server has for us, without waiting: what was written goes
/// out, and the room it frees is counted. False once it has gone away.
fn turn_over(connection: &mut Connection) -> bool {
    loop {
        match connection.mainloop.iterate(false) {
            IterateResult::Success(0) => return true,
            IterateResult::Success(_) => {}
            IterateResult::Quit(_) | IterateResult::Err(_) => return false,
        }
    }
}

/// A stereo playback stream on the sink WebRTC lists as `device_id` (the
/// default when None, or when it is not there any more), holding no more
/// than [`HELD_SAMPLES`].
fn open(connection: &mut Connection, device_id: Option<&str>) -> Result<Stream, String> {
    let sink = pulse::sink_for(connection, device_id);
    let spec = Spec {
        format: Format::S16le,
        channels: CHANNELS as u8,
        rate: SAMPLE_RATE,
    };
    let mut stream = Stream::new(&mut connection.context, "Rift stream", &spec, None)
        .ok_or("could not make a playback stream")?;
    let attr = BufferAttr {
        maxlength: u32::MAX,
        tlength: (HELD_SAMPLES * 2) as u32,
        prebuf: u32::MAX,
        minreq: u32::MAX,
        fragsize: u32::MAX,
    };
    stream
        .connect_playback(
            sink.as_deref(),
            Some(&attr),
            FlagSet::ADJUST_LATENCY,
            None,
            None,
        )
        .map_err(|e| format!("could not open the output: {e:?}"))?;
    loop {
        if !connection.turn() {
            return Err("the sound server went away".to_string());
        }
        match stream.get_state() {
            State::Ready => return Ok(stream),
            State::Failed | State::Terminated => {
                return Err("the output would not start".to_string())
            }
            _ => {}
        }
    }
}
