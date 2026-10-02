//! Linux: reading the microphone through PulseAudio (or PipeWire's PulseAudio
//! server), which resamples and downmixes into the meter's format.
//!
//! The device arrives as WebRTC names it. WebRTC's PulseAudio module reports
//! no id for a source, only its description, so that is what the Dart side
//! holds and what is looked up here. WebRTC's own "default: …" entry, and no
//! device at all, both mean the server's default source — which a record
//! stream opened without naming one follows, as WebRTC's own does.

use super::{samples_from_le_bytes, stopped, SAMPLE_RATE};
use crate::frb_generated::StreamSink;
use crate::pulse::{self, Connection, Device};
use libpulse_binding as pa;
use pa::def::BufferAttr;
use pa::sample::{Format, Spec};
use pa::stream::{FlagSet, PeekResult, State, Stream};
use std::sync::mpsc::Receiver;

/// 20 ms of mono 16-bit audio: how much the server hands over at a time.
const FRAGMENT_BYTES: u32 = SAMPLE_RATE / 50 * 2;

/// How WebRTC's PulseAudio module labels the extra first entry it lists for
/// the default device.
const WEBRTC_DEFAULT_PREFIX: &str = "default: ";

pub(super) fn run(
    device_id: Option<&str>,
    sink: &StreamSink<Vec<i16>>,
    stop: &Receiver<()>,
) -> Result<(), String> {
    let mut connection =
        Connection::open("rift-mic-test").ok_or("could not reach the sound server")?;
    let source = match device_id.filter(|id| !id.starts_with(WEBRTC_DEFAULT_PREFIX)) {
        Some(id) => Some(
            source_described(&mut connection, id)
                .ok_or_else(|| format!("no such microphone: {id}"))?,
        ),
        None => None,
    };
    let mut stream = open(&mut connection, source.as_deref())?;

    let result = loop {
        if stopped(stop) {
            break Ok(());
        }
        if !connection.turn() {
            break Err("the sound server went away".to_string());
        }
        match read(&mut stream, sink) {
            Ok(true) => {}
            // Dart stopped listening: nothing left to read for.
            Ok(false) => break Ok(()),
            Err(message) => break Err(message),
        }
    };
    let _ = stream.disconnect();
    result
}

/// Hands everything the stream holds to `sink`. False once Dart has stopped
/// listening.
fn read(stream: &mut Stream, sink: &StreamSink<Vec<i16>>) -> Result<bool, String> {
    loop {
        match stream.peek() {
            Ok(PeekResult::Data(data)) => {
                let samples = samples_from_le_bytes(data);
                let _ = stream.discard();
                if sink.add(samples).is_err() {
                    return Ok(false);
                }
            }
            Ok(PeekResult::Hole(_)) => {
                let _ = stream.discard();
            }
            Ok(PeekResult::Empty) => return Ok(true),
            Err(e) => return Err(format!("reading the microphone failed: {e:?}")),
        }
    }
}

/// A record stream on `source` (the default when None), ready to read.
fn open(connection: &mut Connection, source: Option<&str>) -> Result<Stream, String> {
    let spec = Spec {
        format: Format::S16le,
        channels: 1,
        rate: SAMPLE_RATE,
    };
    let mut stream = Stream::new(&mut connection.context, "mic-test", &spec, None)
        .ok_or("could not make a record stream")?;
    let attr = BufferAttr {
        maxlength: u32::MAX,
        tlength: u32::MAX,
        prebuf: u32::MAX,
        minreq: u32::MAX,
        fragsize: FRAGMENT_BYTES,
    };
    stream
        .connect_record(source, Some(&attr), FlagSet::ADJUST_LATENCY)
        .map_err(|e| format!("could not open the microphone: {e:?}"))?;
    loop {
        if !connection.turn() {
            return Err("the sound server went away".to_string());
        }
        match stream.get_state() {
            State::Ready => return Ok(stream),
            State::Failed | State::Terminated => {
                return Err("the microphone would not start".to_string())
            }
            _ => {}
        }
    }
}

/// The name of the source WebRTC lists as `description`.
fn source_described(connection: &mut Connection, description: &str) -> Option<String> {
    pick(&pulse::sources(connection), description)
}

/// The first source described as `description`, as WebRTC would pick it.
fn pick(sources: &[Device], description: &str) -> Option<String> {
    sources
        .iter()
        .find(|source| source.description == description)
        .map(|source| source.name.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source(name: &str, description: &str) -> Device {
        Device {
            name: name.to_string(),
            description: description.to_string(),
            channels: 2,
            rate: 48_000,
        }
    }

    #[test]
    fn picks_the_source_by_description() {
        let sources = [
            source("alsa_input", "Built-in Audio"),
            source("usb_input", "USB Headset"),
        ];
        assert_eq!(pick(&sources, "USB Headset").as_deref(), Some("usb_input"));
        assert_eq!(
            pick(&sources, "Built-in Audio").as_deref(),
            Some("alsa_input")
        );
    }

    #[test]
    fn two_alike_pick_the_first() {
        let sources = [source("usb_a", "Headset"), source("usb_b", "Headset")];
        assert_eq!(pick(&sources, "Headset").as_deref(), Some("usb_a"));
    }

    #[test]
    fn an_unknown_description_picks_nothing() {
        let sources = [source("alsa_input", "Built-in Audio")];
        assert_eq!(pick(&sources, "Unplugged Headset"), None);
    }
}
