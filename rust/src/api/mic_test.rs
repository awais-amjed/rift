//! The settings mic test, outside a call.
//!
//! WebRTC only records while a call is sending, so a mic track made for the
//! test with no call up never receives a sample — the meter stayed dark and
//! Windows recorded that the microphone was never opened. On Windows the test
//! reads the microphone itself, the way the sound share reads an application,
//! and hands the samples to the same meter.
//!
//! It measures the device as Windows delivers it, without WebRTC's noise
//! suppression or gain control: what the test answers is whether Rift hears
//! this microphone at all.

#[cfg(target_os = "windows")]
use crate::mic_test;

use crate::frb_generated::StreamSink;

/// Reads `device_id` — an endpoint id as [`super::audio_endpoints`] reports
/// them, or `None` for Windows' default — and sends 16-bit mono samples at
/// 16 kHz to `sink` until [`stop_mic_test`], or until Dart stops listening.
///
/// A microphone that cannot be opened ends the stream with an error. Off
/// Windows the stream ends with an error straight away, and the caller keeps
/// to WebRTC's own capture.
pub fn mic_test_samples(device_id: Option<String>, sink: StreamSink<Vec<i16>>) {
    #[cfg(target_os = "windows")]
    {
        mic_test::start(device_id, sink);
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = device_id;
        let _ = sink.add_error("The mic test reads the device itself only on Windows".to_string());
    }
}

/// Stops the running test, if any, and releases the microphone.
pub fn stop_mic_test() {
    #[cfg(target_os = "windows")]
    mic_test::stop();
}
