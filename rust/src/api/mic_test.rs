//! The settings mic test, outside a call.
//!
//! WebRTC only records while a call is sending, so a mic track made for the
//! test with no call up never receives a sample — the meter stayed dark and
//! Windows recorded that the microphone was never opened. On Windows and
//! Linux the test reads the microphone itself, the way the sound share reads
//! an application, and hands the samples to the same meter.
//!
//! It measures the device as the system delivers it, without WebRTC's noise
//! suppression or gain control: what the test answers is whether Rift hears
//! this microphone at all. It plays the same samples back, so you hear what
//! Rift hears.

#[cfg(any(target_os = "windows", target_os = "linux"))]
use crate::mic_test;

use crate::frb_generated::StreamSink;

/// Where the test plays the microphone back.
pub struct MicTestPlayback {
    /// The id WebRTC lists the output under, or None for the default — as
    /// `play_cue` takes it. One that has gone plays on the default.
    pub device_id: Option<String>,
    /// 0 to 1.
    pub volume: f32,
}

/// Reads `device_id` — the id WebRTC lists the input under, or `None` for the
/// system default — and sends 16-bit mono samples at 16 kHz to `sink` until
/// [`stop_mic_test`], or until Dart stops listening. On Windows that id is the
/// endpoint id; on Linux it is the source's description, the only name
/// WebRTC's PulseAudio module gives one. With `playback`, the samples are
/// played there too, a few tens of milliseconds behind.
///
/// A microphone that cannot be opened ends the stream with an error. Off
/// Windows and Linux the stream ends with an error straight away, and the
/// caller keeps to WebRTC's own capture.
pub fn mic_test_samples(
    device_id: Option<String>,
    playback: Option<MicTestPlayback>,
    sink: StreamSink<Vec<i16>>,
) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        let playback = playback.map(|p| mic_test::Playback {
            device_id: p.device_id,
            volume: p.volume,
        });
        mic_test::start(device_id, playback, sink);
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        let _ = (device_id, playback);
        let _ = sink.add_error(
            "The mic test reads the device itself only on Windows and Linux".to_string(),
        );
    }
}

/// Stops the running test, if any, and releases the microphone.
pub fn stop_mic_test() {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    mic_test::stop();
}
