//! System-audio capture for a screen share: what both platforms share.
//!
//! Each platform supplies one thing, a thread that produces 16-bit stereo PCM
//! at 48 kHz. Publishing the track and feeding LiveKit is the same on both
//! and lives here, so it exists once.
use crate::api::screenshare::types::{AudioSource, ScreenShareConfig};
use livekit::options::TrackPublishOptions;
use livekit::prelude::*;
use livekit::track::{LocalAudioTrack, LocalTrack, TrackSource};
use livekit::webrtc::audio_frame::AudioFrame;
use livekit::webrtc::audio_source::native::NativeAudioSource;
use livekit::webrtc::audio_source::{AudioSourceOptions, RtcAudioSource};
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread::JoinHandle;
use tokio::sync::mpsc::Sender as FrameSender;
use tokio::task::JoinHandle as TaskHandle;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
mod pulse;
#[cfg(target_os = "windows")]
mod windows;

pub(crate) const SAMPLE_RATE: u32 = 48_000;
pub(crate) const NUM_CHANNELS: u32 = 2;
/// LiveKit's source buffers this much before it needs the next frame, which
/// also lets the platforms hand over frames of whatever length they get.
const QUEUE_MS: u32 = 100;
/// PCM frames in flight between the capture thread and the feed task.
const FRAMES_IN_FLIGHT: usize = 100;

pub(crate) enum Command {
    Terminate,
}

/// A platform's capture thread: reads audio until told to stop or until the
/// receiver goes away, and sends interleaved samples down `frames`.
pub(crate) type SpawnCapture =
    Box<dyn FnOnce(Receiver<Command>, FrameSender<Vec<i16>>) -> JoinHandle<()> + Send>;

/// A running audio capture: the platform thread plus the task feeding LiveKit.
pub(crate) struct AudioCaptureHandle {
    command_tx: Sender<Command>,
    capture_thread: JoinHandle<()>,
    feed_task: TaskHandle<()>,
}

impl AudioCaptureHandle {
    pub(crate) fn terminate(self) {
        let _ = self.command_tx.send(Command::Terminate);
        // Dropping the feed task drops its receiver, which also unblocks a
        // capture thread that is mid-send.
        self.feed_task.abort();
        if self.capture_thread.join().is_err() {
            log::warn!("audio: capture thread panicked");
        }
    }
}

/// Start capturing whatever `config` asks for on this platform. `None` when
/// nothing was selected or the platform could not open it; the video share
/// carries on either way.
pub(crate) async fn start(room: &Room, config: &ScreenShareConfig) -> Option<AudioCaptureHandle> {
    #[cfg(target_os = "linux")]
    {
        linux::start(room, config).await
    }
    #[cfg(target_os = "windows")]
    {
        windows::start(room, config).await
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        let _ = (room, config);
        log::info!("audio: system audio capture is not available on this platform");
        None
    }
}

/// Applications currently playing, on the platform that can list them.
pub(crate) fn list_sources() -> Vec<AudioSource> {
    #[cfg(target_os = "linux")]
    {
        pulse::list_sink_inputs()
    }
    #[cfg(not(target_os = "linux"))]
    {
        Vec::new()
    }
}

/// `(window title, process id)` for every visible window, so a picked window
/// can be matched to the process whose audio to capture. Windows only.
pub(crate) fn window_pids() -> Vec<(String, u32)> {
    #[cfg(target_os = "windows")]
    {
        windows::list_windows()
    }
    #[cfg(not(target_os = "windows"))]
    {
        Vec::new()
    }
}

/// Publish a screen-share audio track and start the thread that fills it.
pub(crate) async fn publish_and_feed(
    room: &Room,
    spawn: SpawnCapture,
) -> Option<AudioCaptureHandle> {
    let source = NativeAudioSource::new(
        AudioSourceOptions::default(),
        SAMPLE_RATE,
        NUM_CHANNELS,
        QUEUE_MS,
    );
    let track = LocalAudioTrack::create_audio_track(
        "screen_share_audio",
        RtcAudioSource::Native(source.clone()),
    );
    if let Err(e) = room
        .local_participant()
        .publish_track(
            LocalTrack::Audio(track),
            TrackPublishOptions {
                source: TrackSource::ScreenshareAudio,
                ..Default::default()
            },
        )
        .await
    {
        log::warn!("audio: could not publish the track: {e:?}");
        return None;
    }
    log::info!("audio: track published");

    let (command_tx, command_rx) = mpsc::channel();
    let (frame_tx, mut frame_rx) = tokio::sync::mpsc::channel::<Vec<i16>>(FRAMES_IN_FLIGHT);
    let capture_thread = spawn(command_rx, frame_tx);
    let feed_task = tokio::spawn(async move {
        while let Some(samples) = frame_rx.recv().await {
            let frame = AudioFrame {
                samples_per_channel: samples.len() as u32 / NUM_CHANNELS,
                data: samples.as_slice().into(),
                sample_rate: SAMPLE_RATE,
                num_channels: NUM_CHANNELS,
            };
            if let Err(e) = source.capture_frame(&frame).await {
                log::warn!("audio: LiveKit refused a frame: {e}");
            }
        }
    });
    Some(AudioCaptureHandle {
        command_tx,
        capture_thread,
        feed_task,
    })
}

/// Interleaved little-endian 16-bit PCM bytes as samples. A trailing odd
/// byte, which a device should never produce, is dropped.
pub(crate) fn samples_from_le_bytes(bytes: &[u8]) -> Vec<i16> {
    bytes
        .chunks_exact(2)
        .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_become_little_endian_samples() {
        assert_eq!(
            samples_from_le_bytes(&[0x01, 0x00, 0xFF, 0xFF, 0x00, 0x80]),
            [1, -1, i16::MIN]
        );
    }

    #[test]
    fn an_odd_trailing_byte_is_dropped() {
        assert_eq!(samples_from_le_bytes(&[0x01, 0x00, 0x02]), [1]);
    }
}
