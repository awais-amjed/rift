//! Linux: record applications' streams, each through the monitor of the sink
//! it plays to: every stream of the application picked (`linux_app`), or
//! with none picked every application's but Rift's (`linux_all`).
use super::linux_all::{self, Wanted};
use super::linux_app::App;
use super::{AudioCapture, AudioCaptureHandle, NUM_CHANNELS, SAMPLE_RATE};
use crate::pulse::Connection;
use libpulse_binding as pa;
use livekit::prelude::*;
use pa::def::BufferAttr;
use pa::sample::{Format, Spec};
use pa::stream::{FlagSet, Stream};
use std::time::Duration;

/// Ten milliseconds of audio, the size LiveKit likes its frames in.
const FRAME_BYTES: usize = (SAMPLE_RATE as usize / 100) * NUM_CHANNELS as usize * 2;

/// How long a sound share may hear nothing from its application, with no
/// process running it, before it ends: long enough for a loop or a launcher
/// to start its next process, short enough that a share of a program that
/// quit does not stay up for long.
const QUIET_LIMIT: Duration = Duration::from_secs(10);

pub(crate) async fn start(room: &Room, request: AudioCapture) -> Option<AudioCaptureHandle> {
    let wanted = match &request.selection.app {
        None => Wanted::AllButRift,
        Some(picked) => {
            let quiet_limit = request.on_ended.is_some().then_some(QUIET_LIMIT);
            Wanted::App(App::new(picked, quiet_limit))
        }
    };
    super::publish_and_feed(
        room,
        Box::new(move |commands, frames| linux_all::spawn_capture_thread(wanted, commands, frames)),
        &request.track_name,
        request.on_ended,
    )
    .await
}

/// A record stream on `monitor`, restricted to one sink-input.
///
/// Never moved elsewhere. PulseAudio ends a monitor of a sink-input that is
/// gone; PipeWire instead links the record stream to the default output's
/// monitor, and the stream stays ready, so a share of one application went on
/// with everything the desktop played once that application stopped its
/// stream — seen Oct 12 2026 on PipeWire 1.4 with WirePlumber. `DONT_MOVE`
/// stops the relinking (pipewire-pulse makes it `node.dont-reconnect`), and the
/// stream is closed once the sink-input is no longer listed.
///
/// Asked for and not waited on: it is ready some turns later.
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
            // Never moved elsewhere: see above.
            FlagSet::ADJUST_LATENCY | FlagSet::DONT_MOVE,
        )
        .is_err()
    {
        log::warn!("audio: could not open a record stream on {monitor}");
        return None;
    }
    Some(stream)
}
