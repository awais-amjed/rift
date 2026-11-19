//! What crosses the bridge. Everything here exists on every platform because
//! the bindings are generated once; what happens behind it is desktop-only.

/// Codec for the published video track. The Dart settings store these same
/// names as strings, so the mapping there is by name.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoCodec {
    H264,
    H265,
    VP8,
    VP9,
}

/// What a share gives up when the computer or the connection cannot keep up:
/// WebRTC's degradation preference, which LiveKit passes on as it is.
///
/// LiveKit's default for a screen share keeps the picture sharp and drops
/// frames, which suits text and slides and makes a game stutter. Rift starts
/// on [`SharePriority::Smoothness`], since a stream is usually something moving.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SharePriority {
    /// Keep the frame rate; the picture softens instead.
    Smoothness,
    /// Give up a little of each.
    Balanced,
    /// Keep the picture sharp; frames are dropped instead.
    Sharpness,
}

/// Whether a share draws the mouse cursor into its picture.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShareCursor {
    /// Drawn, except in a Windows share of a whole screen while a game has
    /// locked the mouse. Such a game hides the cursor in its own window, but
    /// a capture of the screen draws it anyway, wherever the game holds it.
    Auto,
    Always,
    Never,
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
    /// Linux under Wayland: the restore token of a window Rift already had
    /// the user pick in the desktop's own picker, so the capture opens it
    /// without asking again. None asks.
    pub portal_choice: Option<String>,
    /// Linux under Wayland: capture on Rift's own stream, the picture staying
    /// on the GPU where the encoder can take it. Off, libwebrtc's capturer runs.
    pub gpu_capture: bool,
    pub codec: VideoCodec,
    pub priority: SharePriority,
    pub cursor: ShareCursor,
    /// Linux: the application picked, as it was listed, which names the
    /// program whose streams to capture; none means everything but Rift.
    pub selected_audio_source: Option<AudioSource>,
    /// Windows: the process whose audio to capture; none means everything but Rift.
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

/// Where a running share is taken when its call reconnects somewhere else: a
/// region change or a rejoin puts the call in a room the share's connection
/// is not in. The same address, token and key a start is given.
pub struct ShareRoom {
    pub livekit_url: String,
    pub livekit_token: String,
    pub e2ee_key: Vec<u8>,
    pub e2ee_key_index: i32,
}

/// What can change while a share is running: the picture's size, rate,
/// bitrate and codec, and whether its sound goes with it. The source and
/// priority stay as the share started.
pub struct ShareQuality {
    /// Height cap in rows, as [`ScreenShareConfig::resolution`].
    pub resolution: u32,
    pub fps: u32,
    /// Megabits per second, as [`ScreenShareConfig::bitrate`]: a bigger or
    /// faster picture may be given more.
    pub bitrate: u32,
    /// As [`ScreenShareConfig::codec`]. What comes back is the codec the
    /// picture went out in, which is VP9 if the GPU's encoder would not open.
    pub codec: VideoCodec,
    pub share_audio: bool,
}

/// What a running share is switched to: a source picked as a share's is,
/// and the sound that goes with it. The picture's quality and the
/// connection stay as they are, so viewers keep watching.
pub struct ShareSource {
    /// As [`ScreenShareConfig::capture_full_screen`].
    pub capture_full_screen: bool,
    /// As [`ScreenShareConfig::selected_video_source_index`].
    pub selected_video_source_index: Option<u32>,
    /// As [`ScreenShareConfig::portal_choice`].
    pub portal_choice: Option<String>,
    /// As [`ScreenShareConfig::selected_audio_source`].
    pub selected_audio_source: Option<AudioSource>,
    /// As [`ScreenShareConfig::selected_audio_source_pid`].
    pub selected_audio_source_pid: Option<u32>,
}

impl From<&ScreenShareConfig> for ShareSource {
    fn from(config: &ScreenShareConfig) -> Self {
        Self {
            capture_full_screen: config.capture_full_screen,
            selected_video_source_index: config.selected_video_source_index,
            portal_choice: config.portal_choice.clone(),
            selected_audio_source: config.selected_audio_source.clone(),
            selected_audio_source_pid: config.selected_audio_source_pid,
        }
    }
}

/// A screen or window that can be captured.
#[derive(Clone, Debug)]
pub struct CaptureSource {
    pub index: u32,
    pub title: String,
    /// The owning process: on Windows for app-loopback audio capture, and on
    /// Windows and X11 to find the sound that goes with the window.
    pub audio_source_pid: Option<u32>,
    /// X11: the app, as the window's `WM_CLASS` names it. Empty elsewhere.
    pub app_id: String,
    /// Windows only: a minimised window. There is no picture of it until it
    /// is back on screen, so a share of it starts paused and begins when the
    /// user opens it.
    pub minimised: bool,
    /// The source the running share captures, which the picker marks when a
    /// share is switched to another.
    pub shared: bool,
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
    /// What the desktop calls the app (`application.id`, else its icon
    /// name), to match against a window's app. Empty where it said neither,
    /// and on Windows.
    pub app_id: String,
    /// The process playing it.
    pub pid: Option<u32>,
    /// False for a program listed while it plays nothing (Linux): it played
    /// before and is running, and a share of it waits for its sound.
    pub playing: bool,
}

/// Lifecycle events pushed from Rust up to Flutter.
pub enum ScreenshareEvent {
    /// The captured window was closed, so capture stopped at the source.
    /// Flutter should tear the session down and update its UI.
    SourceClosed,
    /// H264 was asked for and the GPU could not encode it, at the start or
    /// part way through, so the share went out as VP9 instead.
    EncoderFellBack,
    /// H265 was asked for and could not go out, at the start or part way
    /// through, so the share went out as H264 from the same GPU instead.
    H265FellBack,
    /// The shared window is a game in exclusive full screen, which a window's
    /// capture gets no pictures from: viewers see a still. Once a share.
    ExclusiveFullScreen,
}

const FPS_LIMIT: u32 = 240;
const KEY_BYTES: usize = 32;

/// Refuse a configuration that would fail later in a less legible way: a zero
/// fps is a division by zero in the capture timer, a missing key would connect
/// and then encrypt for nobody.
pub(crate) fn check(config: &ScreenShareConfig) -> Result<(), String> {
    check_picture(config.resolution, config.fps, config.bitrate)?;
    if config.e2ee_key.len() != KEY_BYTES {
        return Err("Missing the channel key for this call".to_string());
    }
    Ok(())
}

/// The same refusal for the room a running share is moved to.
pub(crate) fn check_room(room: &ShareRoom) -> Result<(), String> {
    if room.e2ee_key.len() != KEY_BYTES {
        return Err("Missing the channel key for this call".to_string());
    }
    Ok(())
}

/// The same refusals for a change made during a share.
pub(crate) fn check_quality(quality: &ShareQuality) -> Result<(), String> {
    check_picture(quality.resolution, quality.fps, quality.bitrate)
}

fn check_picture(resolution: u32, fps: u32, bitrate: u32) -> Result<(), String> {
    if bitrate == 0 {
        return Err("bitrate must be at least 1 Mbps".to_string());
    }
    if fps == 0 || fps > FPS_LIMIT {
        return Err(format!("fps must be between 1 and {FPS_LIMIT}"));
    }
    if resolution < 2 {
        return Err("resolution must be at least 2 rows".to_string());
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
            gpu_capture: true,
            resolution: 1080,
            fps: 60,
            bitrate: 10,
            share_audio: false,
            capture_full_screen: true,
            selected_video_source_index: None,
            portal_choice: None,
            codec: VideoCodec::VP9,
            priority: SharePriority::Smoothness,
            cursor: ShareCursor::Always,
            selected_audio_source: None,
            selected_audio_source_pid: None,
            e2ee_key: vec![0; 32],
            e2ee_key_index: 0,
        }
    }

    #[test]
    fn a_share_source_is_what_the_config_picked() {
        let mut c = config();
        c.capture_full_screen = false;
        c.selected_video_source_index = Some(3);
        c.portal_choice = Some("token".to_string());
        c.selected_audio_source_pid = Some(42);
        let source = ShareSource::from(&c);
        assert!(!source.capture_full_screen);
        assert_eq!(source.selected_video_source_index, Some(3));
        assert_eq!(source.portal_choice.as_deref(), Some("token"));
        assert_eq!(source.selected_audio_source_pid, Some(42));
        assert!(source.selected_audio_source.is_none());
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

    #[test]
    fn a_quality_change_is_held_to_the_same_limits() {
        let quality = |resolution, fps, bitrate| ShareQuality {
            resolution,
            fps,
            bitrate,
            codec: VideoCodec::VP9,
            share_audio: false,
        };
        assert!(check_quality(&quality(720, 30, 6)).is_ok());
        assert!(check_quality(&quality(720, 0, 6)).is_err());
        assert!(check_quality(&quality(1, 30, 6)).is_err());
        assert!(check_quality(&quality(720, 30, 0)).is_err());
    }
}
