//! Reading a microphone for the settings mic test. Why it does not go
//! through WebRTC is in `api::mic_test`.
//!
//! Running one test at a time and stopping it is the same everywhere; each
//! platform supplies `run`, which opens the device and reads it until told to
//! stop.

use crate::frb_generated::StreamSink;
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::Mutex;
use std::thread::{self, JoinHandle};

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
use linux::run;
#[cfg(target_os = "windows")]
use windows::run;

/// The meter's format (`micTapFormat` on the Dart side): mono 16-bit at
/// 16 kHz. The platform converts whatever the device runs at.
const SAMPLE_RATE: u32 = 16_000;

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

/// Whether [`stop`] has been called, or the test that owned `stop` is gone.
fn stopped(stop: &Receiver<()>) -> bool {
    !matches!(stop.try_recv(), Err(TryRecvError::Empty))
}

/// Little-endian 16-bit PCM as samples. A trailing odd byte is dropped.
fn samples_from_le_bytes(bytes: &[u8]) -> Vec<i16> {
    bytes
        .chunks_exact(2)
        .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn samples_are_little_endian_pairs() {
        assert_eq!(
            samples_from_le_bytes(&[0x01, 0x00, 0xff, 0x7f, 0x00, 0x80, 0x09]),
            vec![1, i16::MAX, i16::MIN]
        );
    }
}
