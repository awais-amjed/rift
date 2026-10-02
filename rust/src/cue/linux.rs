//! Linux: a playback stream on the chosen sink, through PulseAudio (or
//! PipeWire's PulseAudio server), which converts the cue's format.
//!
//! The device arrives as WebRTC names it: a sink's description, the only
//! name its PulseAudio module gives one. WebRTC's own "default: …" entry, and
//! no device at all, both mean the server's default sink.

use super::{le_bytes, Controls, Cue};
use crate::pulse::{self, Connection};
use libpulse_binding as pa;
use pa::sample::{Format, Spec};
use pa::stream::{FlagSet, SeekMode, State, Stream};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};

/// How WebRTC's PulseAudio module labels the extra first entry it lists for
/// the default device.
const WEBRTC_DEFAULT_PREFIX: &str = "default: ";

pub(super) fn run(
    device_id: Option<&str>,
    cue: &mut Cue,
    controls: &Controls,
    opened: &Sender<Result<(), String>>,
) -> Result<(), String> {
    let mut connection = Connection::open("rift-cue").ok_or("could not reach the sound server")?;
    let sink = match device_id.filter(|id| !id.starts_with(WEBRTC_DEFAULT_PREFIX)) {
        Some(id) => Some(
            pulse::sinks(&mut connection)
                .into_iter()
                .find(|sink| sink.description == id)
                .map(|sink| sink.name)
                .ok_or_else(|| format!("no such output: {id}"))?,
        ),
        None => None,
    };
    let mut stream = open(&mut connection, sink.as_deref(), cue)?;
    let _ = opened.send(Ok(()));

    let result = play(&mut connection, &mut stream, cue, controls);
    let _ = stream.disconnect();
    result
}

/// Feeds the stream until the cue ends, then waits for the server to play
/// what it holds — or stops at once when told to.
fn play(
    connection: &mut Connection,
    stream: &mut Stream,
    cue: &mut Cue,
    controls: &Controls,
) -> Result<(), String> {
    let mut buffer = Vec::new();
    loop {
        if controls.stopped() {
            return Ok(());
        }
        if !connection.turn() {
            return Err("the sound server went away".to_string());
        }
        let room = stream.writable_size().unwrap_or(0) / 2;
        if room == 0 {
            continue;
        }
        buffer.resize(room, 0);
        let written = cue.fill(&mut buffer, controls.volume());
        if written == 0 {
            break;
        }
        stream
            .write(&le_bytes(&buffer[..written]), None, 0, SeekMode::Relative)
            .map_err(|e| format!("writing the cue failed: {e:?}"))?;
    }

    let drained = Arc::new(Mutex::new(false));
    let done = Arc::clone(&drained);
    let _op = stream.drain(Some(Box::new(move |_| *done.lock().unwrap() = true)));
    while !*drained.lock().unwrap() && !controls.stopped() {
        if !connection.turn() {
            return Err("the sound server went away".to_string());
        }
    }
    Ok(())
}

/// A playback stream on `sink` (the default when None), ready to write.
fn open(connection: &mut Connection, sink: Option<&str>, cue: &Cue) -> Result<Stream, String> {
    let spec = Spec {
        format: Format::S16le,
        channels: u8::try_from(cue.channels).map_err(|_| "too many channels")?,
        rate: cue.rate,
    };
    if !spec.is_valid() {
        return Err(format!("not a playable format: {spec:?}"));
    }
    let mut stream = Stream::new(&mut connection.context, "Rift", &spec, None)
        .ok_or("could not make a playback stream")?;
    stream
        .connect_playback(sink, None, FlagSet::NOFLAGS, None, None)
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
