//! What crosses the bridge. Everything here exists on every platform because
//! the bindings are generated once; what happens behind it is desktop-only.

/// Codec for the published video track. The Dart settings store these same
/// names as strings, so the mapping there is by name.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoCodec {
    H264,
    VP8,
    VP9,
}

pub struct ScreenShareConfig {
    pub livekit_url: String,
    pub livekit_token: String,
    /// Height cap in rows (720, 1080, ...). A smaller capture is not upscaled.
    pub resolution: u32,
    pub fps: u32,
    /// Megabits per second.
    pub bitrate: u32,
    pub share_audio: bool,
    pub capture_full_screen: bool,
    /// Index into `list_capture_sources` for the same `capture_full_screen`.
    pub selected_video_source_index: Option<u32>,
    pub codec: VideoCodec,
    /// Linux: the PulseAudio sink-input to capture, and the sink it plays to.
    pub selected_audio_source_index: Option<u32>,
    pub selected_audio_source_sink: Option<u32>,
    /// Windows: the process whose audio to capture; none means the whole mix.
    pub selected_audio_source_pid: Option<u32>,
    /// The channel key this call is encrypted with, and the LiveKit key-ring
    /// slot it occupies (ARCHITECTURE.md §5).
    ///
    /// A screen share is a second connection into the same encrypted room, so
    /// it has to encrypt with the same key as everything else. Publishing it in
    /// the clear would not fail — LiveKit skips the frame cryptor for a track
    /// that declares no encryption — it would simply hand the server the one
    /// stream nobody meant it to have.
    pub e2ee_key: Vec<u8>,
    pub e2ee_key_index: i32,
}

/// A screen or window that can be captured.
#[derive(Clone, Debug)]
pub struct CaptureSource {
    pub index: u32,
    pub title: String,
    /// Windows only: the owning process, for app-loopback audio capture.
    pub audio_source_pid: Option<u32>,
    /// Windows only: a minimised window. There is no picture of it until it
    /// is back on screen, so sharing it restores it.
    pub minimised: bool,
}

/// A PulseAudio sink-input: one application's playback stream. Linux only;
/// Windows picks audio by process id from [`CaptureSource`] instead.
#[derive(Clone, Debug)]
pub struct AudioSource {
    pub index: u32,
    pub sink: u32,
    pub app_name: String,
    pub binary: String,
    pub media_name: String,
}

/// Lifecycle events pushed from Rust up to Flutter.
pub enum ScreenshareEvent {
    /// The captured window was closed, so capture stopped at the source.
    /// Flutter should tear the session down and update its UI.
    SourceClosed,
}

const FPS_LIMIT: u32 = 240;
const KEY_BYTES: usize = 32;

/// Refuse a configuration that would fail later in a less legible way: a zero
/// fps is a division by zero in the capture timer, a missing key would connect
/// and then encrypt for nobody.
pub(crate) fn check(config: &ScreenShareConfig) -> Result<(), String> {
    if config.fps == 0 || config.fps > FPS_LIMIT {
        return Err(format!("fps must be between 1 and {FPS_LIMIT}"));
    }
    if config.resolution < 2 {
        return Err("resolution must be at least 2 rows".to_string());
    }
    if config.bitrate == 0 {
        return Err("bitrate must be at least 1 Mbps".to_string());
    }
    if config.e2ee_key.len() != KEY_BYTES {
        return Err("Missing the channel key for this call".to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> ScreenShareConfig {
        ScreenShareConfig {
            livekit_url: String::new(),
            livekit_token: String::new(),
            resolution: 1080,
            fps: 60,
            bitrate: 10,
            share_audio: false,
            capture_full_screen: true,
            selected_video_source_index: None,
            codec: VideoCodec::VP9,
            selected_audio_source_index: None,
            selected_audio_source_sink: None,
            selected_audio_source_pid: None,
            e2ee_key: vec![0; 32],
            e2ee_key_index: 0,
        }
    }

    #[test]
    fn a_sane_config_passes() {
        assert!(check(&config()).is_ok());
    }

    #[test]
    fn zero_fps_is_refused() {
        let mut c = config();
        c.fps = 0;
        assert!(check(&c).is_err());
    }

    #[test]
    fn a_short_key_is_refused() {
        let mut c = config();
        c.e2ee_key = vec![0; 16];
        assert!(check(&c).unwrap_err().contains("key"));
    }
}
