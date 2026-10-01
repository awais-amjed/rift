//! Reading a microphone for the settings mic test. Why it does not go
//! through WebRTC is in `api::mic_test`.

use crate::frb_generated::StreamSink;
use std::sync::mpsc::{self, Sender, TryRecvError};
use std::sync::Mutex;
use std::thread::{self, JoinHandle};
use std::time::Duration;
use wasapi::{DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat};

/// The meter's format (`micTapFormat` on the Dart side): mono 16-bit at
/// 16 kHz. Windows converts whatever the device runs at.
const SAMPLE_RATE: usize = 16_000;
const POLL: Duration = Duration::from_millis(10);
/// One second, in the 100 ns units WASAPI counts in.
const BUFFER_DURATION_HNS: i64 = 10_000_000;
const READ_BUFFER_BYTES: usize = 8 * 1024;

/// The running test: how to stop it, and the thread to wait for.
static RUNNING: Mutex<Option<(Sender<()>, JoinHandle<()>)>> = Mutex::new(None);

pub(crate) fn start(device_id: Option<String>, sink: StreamSink<Vec<i16>>) {
    // One test at a time; a new one replaces the old.
    stop();
    let (stop_tx, stop_rx) = mpsc::channel();
    let thread = thread::spawn(move || {
        if let Err(message) = run(device_id.as_deref(), &sink, &stop_rx) {
            log::warn!("mic test: {message}");
            let _ = sink.add_error(message);
        }
    });
    *RUNNING.lock().unwrap() = Some((stop_tx, thread));
}

pub(crate) fn stop() {
    let running = RUNNING.lock().unwrap().take();
    if let Some((stop_tx, thread)) = running {
        let _ = stop_tx.send(());
        let _ = thread.join();
    }
}

fn run(
    device_id: Option<&str>,
    sink: &StreamSink<Vec<i16>>,
    stop: &mpsc::Receiver<()>,
) -> Result<(), String> {
    // See `audio_endpoints::list` on why the result is not checked.
    let _ = wasapi::initialize_mta().ok();
    let enumerator = DeviceEnumerator::new().map_err(|e| format!("no device enumerator: {e:?}"))?;
    let device = match device_id {
        Some(id) => enumerator.get_device(id),
        None => enumerator.get_default_device(&Direction::Capture),
    }
    .map_err(|e| format!("no such microphone: {e:?}"))?;
    let mut client = device
        .get_iaudioclient()
        .map_err(|e| format!("could not open the microphone: {e:?}"))?;
    let format = WaveFormat::new(16, 16, &SampleType::Int, SAMPLE_RATE, 1, None);
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
        match stop.try_recv() {
            Ok(()) | Err(TryRecvError::Disconnected) => break,
            Err(TryRecvError::Empty) => {}
        }
        if let Ok((frames, _)) = capture.read_from_device(&mut buffer) {
            if frames > 0 {
                let bytes = frames as usize * 2;
                let samples = buffer[..bytes]
                    .chunks_exact(2)
                    .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
                    .collect();
                // Dart stopped listening: nothing left to read for.
                if sink.add(samples).is_err() {
                    break;
                }
            }
        }
        thread::sleep(POLL);
    }
    let _ = client.stop_stream();
    Ok(())
}
