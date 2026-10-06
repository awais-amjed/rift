//! Windows: reading the microphone through WASAPI, which converts whatever
//! the device runs at into the meter's format, and playing it back on a
//! render stream polled from the same loop.

use super::{
    for_playback, samples_from_le_bytes, stopped, Playback, PLAYBACK_SAMPLES, SAMPLE_RATE,
};
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
const READ_BUFFER_BYTES: usize = 8 * 1024;

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
    loop {
        if stopped(stop) {
            break;
        }
        if let Ok((frames, _)) = capture.read_from_device(&mut buffer) {
            if frames > 0 {
                let bytes = frames as usize * 2;
                let samples = samples_from_le_bytes(&buffer[..bytes]);
                if let Some(((out_client, render), volume)) = &output {
                    let room = out_client
                        .get_available_space_in_frames()
                        .map_or(0, |free| free as usize);
                    let played = for_playback(&samples, room, *volume);
                    if !played.is_empty() {
                        let _ = render.write_to_device(played.len(), &le_bytes(&played), None);
                    }
                }
                // Dart stopped listening: nothing left to read for.
                if sink.add(samples).is_err() {
                    break;
                }
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

/// A render stream for the voice on the chosen output, started, holding no
/// more than [`PLAYBACK_SAMPLES`]. An output that is not there any more plays
/// on the default instead: the test is about the microphone.
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
        buffer_duration_hns: PLAYBACK_SAMPLES as i64 * 10_000_000 / i64::from(SAMPLE_RATE),
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
