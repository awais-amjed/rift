//! Capturing an application's sound: what both platforms share.
//!
//! Each platform supplies one thing, a thread that produces 16-bit stereo PCM
//! at 48 kHz. Publishing the track and feeding LiveKit is the same on both
//! and lives here, so it exists once — for the audio that rides along with a
//! screen share, and for a sound share, which is only this.
use crate::api::screenshare::types::{AudioSource, ScreenShareConfig};
use crate::api::soundshare::SoundShareConfig;
use livekit::options::TrackPublishOptions;
use livekit::prelude::*;
use livekit::track::{LocalAudioTrack, LocalTrack, TrackSource};
use livekit::webrtc::audio_frame::AudioFrame;
use livekit::webrtc::audio_source::native::NativeAudioSource;
use livekit::webrtc::audio_source::{AudioSourceOptions, RtcAudioSource};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Arc;
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

/// Which application's sound to capture, as each platform asks for it.
///
/// The two kinds of share choose it differently — a screen share takes the
/// audio belonging to the window it is capturing, a sound share is the choice
/// itself — so they both narrow down to this before any of the code below
/// cares which one it is serving.
// Each platform reads its own fields and ignores the others, so on any one of
// them some of these are dead by definition.
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct AudioSelection {
    /// Linux: the PulseAudio sink-input to capture, and the sink it plays to.
    pub sink_input: Option<u32>,
    pub sink: Option<u32>,
    /// Windows: the process whose audio to capture; none means the whole mix.
    pub pid: Option<u32>,
}

impl From<&ScreenShareConfig> for AudioSelection {
    fn from(config: &ScreenShareConfig) -> Self {
        Self {
            sink_input: config.selected_audio_source_index,
            sink: config.selected_audio_source_sink,
            pid: config.selected_audio_source_pid,
        }
    }
}

impl From<&SoundShareConfig> for AudioSelection {
    fn from(config: &SoundShareConfig) -> Self {
        Self {
            sink_input: config.selected_audio_source_index,
            sink: config.selected_audio_source_sink,
            pid: config.selected_audio_source_pid,
        }
    }
}

/// A platform's capture thread: reads audio until told to stop or until the
/// receiver goes away, and sends interleaved samples down `frames`.
pub(crate) type SpawnCapture =
    Box<dyn FnOnce(Receiver<Command>, FrameSender<Vec<i16>>) -> JoinHandle<()> + Send>;

/// What a capture that stops on its own calls, on the feed task. The source
/// going away — the application closing, the stream ending — reaches us as the
/// capture thread finishing without having been asked to.
pub(crate) type OnEnded = Box<dyn Fn() + Send + 'static>;

/// A running audio capture: the platform thread plus the task feeding LiveKit.
pub(crate) struct AudioCaptureHandle {
    command_tx: Sender<Command>,
    capture_thread: JoinHandle<()>,
    feed_task: TaskHandle<()>,
    /// Set before the thread is asked to stop, so the feed task can tell a
    /// teardown from the source disappearing underneath it.
    stopping: Arc<AtomicBool>,
}

impl AudioCaptureHandle {
    pub(crate) fn terminate(self) {
        self.stopping.store(true, Ordering::SeqCst);
        let _ = self.command_tx.send(Command::Terminate);
        // Dropping the feed task drops its receiver, which also unblocks a
        // capture thread that is mid-send.
        self.feed_task.abort();
        if self.capture_thread.join().is_err() {
            log::warn!("audio: capture thread panicked");
        }
    }
}

/// One request to capture an application's sound.
pub(crate) struct AudioCapture {
    pub selection: AudioSelection,

    /// What to call the published track. A sound share puts the application's
    /// name here — it is the only way everyone else's tile can say what is
    /// playing rather than just whose it is.
    pub track_name: String,

    /// Runs if the capture stops by itself — for a sound share, which *is* the
    /// capture, that is the share ending.
    pub on_ended: Option<OnEnded>,
}

/// Start capturing what [`request`] asks for and publish it into `room`.
/// `None` when nothing was selected or the platform could not open it; a
/// screen share carries on without its sound either way.
pub(crate) async fn start(room: &Room, request: AudioCapture) -> Option<AudioCaptureHandle> {
    #[cfg(target_os = "linux")]
    {
        linux::start(room, request).await
    }
    #[cfg(target_os = "windows")]
    {
        windows::start(room, request).await
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        let _ = (room, request);
        log::info!("audio: system audio capture is not available on this platform");
        None
    }
}

/// Applications currently playing. On Linux each is a PulseAudio sink input;
/// on Windows each is a process, with its id in `index` (see
/// [`windows::list_sources`]).
pub(crate) fn list_sources() -> Vec<AudioSource> {
    #[cfg(target_os = "linux")]
    {
        pulse::list_sink_inputs()
    }
    #[cfg(target_os = "windows")]
    {
        windows::list_sources()
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        Vec::new()
    }
}

/// Publish a screen-share audio track and start the thread that fills it.
///
/// The source is `ScreenshareAudio` for a sound share too: LiveKit has no
/// source for "an application's sound", and this is the one every client
/// already treats as audio that is not somebody's microphone — including the
/// server, which leaves it alone when it takes a muted member's mic away.
pub(crate) async fn publish_and_feed(
    room: &Room,
    spawn: SpawnCapture,
    track_name: &str,
    on_ended: Option<OnEnded>,
) -> Option<AudioCaptureHandle> {
    let source = NativeAudioSource::new(
        AudioSourceOptions::default(),
        SAMPLE_RATE,
        NUM_CHANNELS,
        QUEUE_MS,
    );
    let track =
        LocalAudioTrack::create_audio_track(track_name, RtcAudioSource::Native(source.clone()));
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
    let stopping = Arc::new(AtomicBool::new(false));
    let ended_flag = Arc::clone(&stopping);
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
        // The channel closed, so the capture thread is gone. If nobody asked
        // it to stop, the source went away — the application quit, or the
        // stream it was playing ended.
        if !ended_flag.load(Ordering::SeqCst) {
            log::info!("audio: the captured source stopped");
            if let Some(on_ended) = on_ended {
                on_ended();
            }
        }
    });
    Some(AudioCaptureHandle {
        command_tx,
        capture_thread,
        feed_task,
        stopping,
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
