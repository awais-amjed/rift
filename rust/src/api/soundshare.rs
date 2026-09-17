//! The sound-share bridge: sharing what an application is playing, with no
//! picture attached.
//!
//! A sound share is the audio half of a screen share on its own — a second
//! connection into the call publishing one track, so a room can listen to
//! music somebody has on without them also handing over their screen. The
//! applications to choose from are the ones `list_audio_sources` already
//! lists for a screen share's audio.
//!
//! Like the screenshare bridge, these functions exist on every platform
//! because the bindings are generated once; behind them is `cfg(desktop)`,
//! since capturing another application's output is something only a desktop
//! can do.
#[cfg(desktop)]
use crate::sharing::sound;

use crate::frb_generated::StreamSink;
use std::sync::Mutex;

/// What to share, and the call to share it into.
pub struct SoundShareConfig {
    pub livekit_url: String,
    pub livekit_token: String,
    /// Linux: the PulseAudio sink-input to capture, and the sink it plays to.
    pub selected_audio_source_index: Option<u32>,
    pub selected_audio_source_sink: Option<u32>,
    /// Windows: the process whose audio to capture; none means the whole mix.
    pub selected_audio_source_pid: Option<u32>,

    /// What the application calls itself, published as the track's name so
    /// that everyone else's tile can say what is playing and not merely whose
    /// it is. Empty is allowed: the tile then falls back to its owner's name.
    pub source_label: String,
    /// The channel key this call is encrypted with, and the LiveKit key-ring
    /// slot it occupies (ARCHITECTURE.md §5) — the same pair a screen share
    /// carries, and for the same reason: a track published in the clear is
    /// one the server can listen to.
    pub e2ee_key: Vec<u8>,
    pub e2ee_key_index: i32,
}

/// Lifecycle events pushed from Rust up to Flutter.
pub enum SoundShareEvent {
    /// The application stopped playing, or quit. There is nothing left to
    /// share, so Flutter tears the session down and updates its UI.
    SourceEnded,
}

// Set once when Flutter subscribes; replaced if it subscribes again.
static EVENT_SINK: Mutex<Option<StreamSink<SoundShareEvent>>> = Mutex::new(None);

/// Subscribe to sound-share lifecycle events. Flutter listens to the returned
/// stream for the app's lifetime.
pub fn sound_share_event_stream(sink: StreamSink<SoundShareEvent>) {
    *EVENT_SINK.lock().unwrap() = Some(sink);
}

/// Emit an event to Flutter if a listener is attached. Safe from any thread.
pub(crate) fn emit_event(event: SoundShareEvent) {
    if let Some(sink) = EVENT_SINK.lock().unwrap().as_ref() {
        let _ = sink.add(event);
    }
}

/// Connect a second participant to the call's room and publish one
/// application's sound.
///
/// Only one sound share runs at a time; a second call while one is up is an
/// error rather than a replacement. A screen share may run alongside it —
/// they are separate connections with identities of their own.
pub async fn start_sound_share(config: SoundShareConfig) -> Result<String, String> {
    #[cfg(desktop)]
    {
        sound::start(config).await
    }
    #[cfg(not(desktop))]
    {
        let _ = config;
        Err("Sharing sound is desktop-only on this build".to_string())
    }
}

/// Stop the share and leave the room. Succeeds when nothing was running: a
/// teardown that errors would make every disconnect look like a failure.
pub async fn stop_sound_share() -> Result<String, String> {
    #[cfg(desktop)]
    {
        sound::stop().await
    }
    #[cfg(not(desktop))]
    {
        Ok("No active session".to_string())
    }
}

const KEY_BYTES: usize = 32;

/// Refuse a configuration that would fail later in a less legible way: a
/// missing key would connect and then encrypt for nobody.
pub(crate) fn check(config: &SoundShareConfig) -> Result<(), String> {
    if config.e2ee_key.len() != KEY_BYTES {
        return Err("Missing the channel key for this call".to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> SoundShareConfig {
        SoundShareConfig {
            livekit_url: String::new(),
            livekit_token: String::new(),
            selected_audio_source_index: Some(1),
            selected_audio_source_sink: Some(0),
            selected_audio_source_pid: None,
            source_label: "Spotify".to_string(),
            e2ee_key: vec![0; 32],
            e2ee_key_index: 0,
        }
    }

    #[test]
    fn a_sane_config_passes() {
        assert!(check(&config()).is_ok());
    }

    #[test]
    fn a_short_key_is_refused() {
        let mut c = config();
        c.e2ee_key = vec![0; 16];
        assert!(check(&c).unwrap_err().contains("key"));
    }
}
