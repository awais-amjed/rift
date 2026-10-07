//! The settings mic test, outside a call.
//!
//! WebRTC only records while a call is sending, so a mic track made for the
//! test with no call up never receives a sample — the meter stayed dark and
//! Windows recorded that the microphone was never opened. On Windows and
//! Linux the test reads the microphone itself, the way the sound share reads
//! an application, and hands the samples to the same meter.
//!
//! What it reads goes through what the call would do to it — libwebrtc's own
//! processing, the noise model and the mic volume (`mic_test::clean`) — and
//! it plays the result back, so you hear how you will sound.

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
/// system default — and sends 16-bit mono samples at 48 kHz, processed as
/// [`set_mic_test_processing`] last said, to `sink` until
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

/// The mic volume, as a gain: what the test reads is turned up or down by it,
/// meter and playback alike, as the call is by the runner's filter. Reaches a
/// test already running.
pub fn set_mic_test_gain(gain: f32) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    mic_test::set_gain(gain);
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = gain;
}

/// Which noise filter the test runs, as the call would run it on this device.
pub enum MicTestNoise {
    Off,
    /// libwebrtc's own suppressor.
    Standard,
    Rnnoise,
    DeepFilter,
}

/// How the test processes the microphone: the noise filter, and whether gain
/// control is on. Reaches a test already running, so a change in settings is
/// heard straight away.
pub fn set_mic_test_processing(noise: MicTestNoise, auto_gain: bool) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    mic_test::set_processing(mic_test::Settings {
        noise: match noise {
            MicTestNoise::Off => mic_test::Noise::Off,
            MicTestNoise::Standard => mic_test::Noise::Standard,
            MicTestNoise::Rnnoise => mic_test::Noise::Rnnoise,
            MicTestNoise::DeepFilter => mic_test::Noise::DeepFilter,
        },
        auto_gain,
    });
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = (noise, auto_gain);
}

/// Where the runner's RNNoise is: the addresses of its
/// `rift_noise_filter_rnnoise_create`, `_process` and `_destroy`, which Dart
/// looks up in the executable. The model is built into the runner, so the test borrows it
/// rather than the library carrying a second copy.
pub fn set_mic_test_rnnoise(create: usize, process: usize, destroy: usize) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    mic_test::set_rnnoise(create, process, destroy);
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = (create, process, destroy);
}
