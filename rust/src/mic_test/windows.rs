//! Windows: reading the microphone through WASAPI, which converts whatever
//! the device runs at into the meter's format.

use super::{samples_from_le_bytes, stopped, SAMPLE_RATE};
use crate::frb_generated::StreamSink;
use std::sync::mpsc::Receiver;
use std::thread;
use std::time::Duration;
use wasapi::{DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat};

const POLL: Duration = Duration::from_millis(10);
/// One second, in the 100 ns units WASAPI counts in.
const BUFFER_DURATION_HNS: i64 = 10_000_000;
const READ_BUFFER_BYTES: usize = 8 * 1024;

pub(super) fn run(
    device_id: Option<&str>,
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
                // Dart stopped listening: nothing left to read for.
                if sink.add(samples_from_le_bytes(&buffer[..bytes])).is_err() {
                    break;
                }
            }
        }
        thread::sleep(POLL);
    }
    let _ = client.stop_stream();
    Ok(())
}
