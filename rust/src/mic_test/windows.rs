//! Windows: reading the microphone through WASAPI, which converts whatever
//! the device runs at into the format the processing works in, and playing it
//! back on a
//! render stream polled from the same loop.

use super::{for_playback, samples_from_le_bytes, stopped, Cleaner, Playback, SAMPLE_RATE};
use crate::cue::le_bytes;
use crate::frb_generated::StreamSink;
use std::sync::mpsc::Receiver;
use std::thread;
use std::time::Duration;
use wasapi::{
    AudioClient, AudioRenderClient, DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat,
};

const POLL: Duration = Duration::from_millis(10);
/// One second, in the 100 ns units WASAPI counts in.
const BUFFER_DURATION_HNS: i64 = 10_000_000;
/// Room for a packet of up to 80 ms; WASAPI hands over about 10.
const READ_BUFFER_BYTES: usize = 8 * 1024;
/// How far behind the voice its playback may fall: 100 ms. Counted from what
/// the output holds rather than set as its buffer, which Windows' engine
/// empties in uneven gulps: a buffer that small was often full when the next
/// packet came, and the voice was cut.
const MAX_QUEUED_SAMPLES: usize = SAMPLE_RATE as usize / 10;
/// Silence put ahead of the voice when the output holds nothing — at the
/// start, and after it ran dry: 30 ms. Without it the voice is played the
/// moment it lands, so the output never holds more than a packet, and one
/// that arrives late is a click. PulseAudio prebuffers the same way on Linux.
const CUSHION_SAMPLES: usize = SAMPLE_RATE as usize * 3 / 100;

pub(super) fn run(
    device_id: Option<&str>,
    playback: Option<&Playback>,
    sink: &StreamSink<Vec<i16>>,
    stop: &Receiver<()>,
) -> Result<(), String> {
    // See `audio_endpoints::list` on why the result is not checked.
    let _ = wasapi::initialize_mta().ok();
    let enumerator = DeviceEnumerator::new().map_err(|e| format!("no device enumerator: {e:?}"))?;
    let device = match device_id {
        Some(id) => crate::audio_endpoints::device_by_id(&Direction::Capture, id),
        None => enumerator
            .get_default_device(&Direction::Capture)
            .map_err(|e| format!("{e:?}")),
    }
    .map_err(|e| format!("no such microphone: {e}"))?;
    let mut client = device
        .get_iaudioclient()
        .map_err(|e| format!("could not open the microphone: {e:?}"))?;
    let format = WaveFormat::new(16, 16, &SampleType::Int, SAMPLE_RATE as usize, 1, None);
    let mode = StreamMode::PollingShared {
        autoconvert: true,
        buffer_duration_hns: BUFFER_DURATION_HNS,
    };
    client
        .initialize_client(&format, &Direction::Capture, &mode)
        .map_err(|e| format!("the microphone refused the format: {e:?}"))?;
    let capture = client
        .get_audiocaptureclient()
        .map_err(|e| format!("no capture client: {e:?}"))?;
    let output = match playback {
        Some(playback) => Some((open_output(&enumerator, playback)?, playback.volume)),
        None => None,
    };
    client
        .start_stream()
        .map_err(|e| format!("the microphone would not start: {e:?}"))?;

    let mut buffer = vec![0u8; READ_BUFFER_BYTES];
    let mut cleaner = Cleaner::new();
    'test: loop {
        if stopped(stop) {
            break;
        }
        // Each read hands over one packet, about 10 ms, so a pass reads until
        // none is left. Reading one a pass fell behind the device until its
        // buffer overflowed: a second late, then in pieces. The meter hid
        // that; playback does not.
        while let Ok((frames, _)) = capture.read_from_device(&mut buffer) {
            if frames == 0 {
                break;
            }
            let bytes = frames as usize * 2;
            let samples = cleaner.clean(&samples_from_le_bytes(&buffer[..bytes]));
            if samples.is_empty() {
                continue;
            }
            if let Some(((out_client, render), volume)) = &output {
                let queued = out_client
                    .get_current_padding()
                    .map_or(MAX_QUEUED_SAMPLES, |queued| queued as usize);
                let room = MAX_QUEUED_SAMPLES.saturating_sub(queued);
                let cushion = if queued == 0 { CUSHION_SAMPLES } else { 0 };
                let mut played = vec![0; cushion.min(room)];
                played.extend(for_playback(&samples, room - played.len(), *volume));
                if !played.is_empty() {
                    let _ = render.write_to_device(played.len(), &le_bytes(&played), None);
                }
            }
            // Dart stopped listening: nothing left to read for.
            if sink.add(samples).is_err() {
                break 'test;
            }
        }
        thread::sleep(POLL);
    }
    let _ = client.stop_stream();
    if let Some(((out_client, _), _)) = &output {
        let _ = out_client.stop_stream();
    }
    Ok(())
}

/// A render stream for the voice on the chosen output, started. An output
/// that is not there any more plays on the default instead: the test is about
/// the microphone.
fn open_output(
    enumerator: &DeviceEnumerator,
    playback: &Playback,
) -> Result<(AudioClient, AudioRenderClient), String> {
    let chosen = playback.device_id.as_deref().and_then(|id| {
        let device = crate::audio_endpoints::device_by_id(&Direction::Render, id).ok();
        if device.is_none() {
            log::warn!("mic test: no output {id}, playing on the default");
        }
        device
    });
    let device = match chosen {
        Some(device) => device,
        None => enumerator
            .get_default_device(&Direction::Render)
            .map_err(|e| format!("no output: {e:?}"))?,
    };
    let mut client = device
        .get_iaudioclient()
        .map_err(|e| format!("could not open the output: {e:?}"))?;
    let format = WaveFormat::new(16, 16, &SampleType::Int, SAMPLE_RATE as usize, 1, None);
    let mode = StreamMode::PollingShared {
        autoconvert: true,
        buffer_duration_hns: BUFFER_DURATION_HNS,
    };
    client
        .initialize_client(&format, &Direction::Render, &mode)
        .map_err(|e| format!("the output refused the format: {e:?}"))?;
    let render = client
        .get_audiorenderclient()
        .map_err(|e| format!("no render client: {e:?}"))?;
    client
        .start_stream()
        .map_err(|e| format!("the output would not start: {e:?}"))?;
    Ok((client, render))
}
