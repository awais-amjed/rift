//! The screenshare bridge: every function Dart can call, each exactly once.
//!
//! These exist on every platform because the bindings are generated once and
//! are not conditional. What sits behind them is `cfg(desktop)` (see
//! build.rs): capturing a desktop needs libwebrtc's `desktop_capturer`, which
//! exists only on Windows, Linux and macOS, so a phone gets the same API
//! answering "there is no desktop here" and shares its screen through the
//! Dart SDK instead.
pub mod types;

#[cfg(target_os = "windows")]
use crate::screenshare::thumbnail;
#[cfg(desktop)]
use crate::screenshare::{session, sources};
#[cfg(desktop)]
use crate::sharing::audio;

use crate::frb_generated::StreamSink;
use std::sync::Mutex;
use types::{AudioSource, CaptureSource, ScreenShareConfig, ScreenshareEvent, ShareQuality};

// Set once when Flutter subscribes; replaced if it subscribes again.
static EVENT_SINK: Mutex<Option<StreamSink<ScreenshareEvent>>> = Mutex::new(None);

/// Subscribe to screenshare lifecycle events (e.g. the shared window closing).
/// Flutter listens to the returned stream for the app's lifetime.
pub fn screenshare_event_stream(sink: StreamSink<ScreenshareEvent>) {
    *EVENT_SINK.lock().unwrap() = Some(sink);
}

/// Emit an event to Flutter if a listener is attached. Safe from any thread.
pub(crate) fn emit_screenshare_event(event: ScreenshareEvent) {
    if let Some(sink) = EVENT_SINK.lock().unwrap().as_ref() {
        let _ = sink.add(event);
    }
}

/// Connect a second participant to the call's room and publish the chosen
/// screen or window (and, if asked, its audio) as screen-share tracks.
///
/// Only one share runs at a time; a second call while one is up is an error
/// rather than a replacement. Off the desktop it fails outright: the caller is
/// about to show a "sharing" state for a stream that would never arrive.
pub async fn start_screenshare(config: ScreenShareConfig) -> Result<String, String> {
    #[cfg(desktop)]
    {
        session::start(config).await
    }
    #[cfg(not(desktop))]
    {
        let _ = config;
        Err("Screen sharing from Rust is desktop-only on this build".to_string())
    }
}

/// Change a running share's frame rate, size or sound without stopping it,
/// and return what is now in effect. The capture carries on, so a desktop
/// portal is not asked again; viewers see the picture blink while its track
/// is published again at the new size.
pub async fn update_screenshare(quality: ShareQuality) -> Result<ShareQuality, String> {
    #[cfg(desktop)]
    {
        session::update(quality).await
    }
    #[cfg(not(desktop))]
    {
        let _ = quality;
        Err("Screen sharing from Rust is desktop-only on this build".to_string())
    }
}

/// Stop the share and leave the room. Succeeds when nothing was running: a
/// teardown that errors would make every disconnect look like a failure.
pub async fn stop_screenshare() -> Result<String, String> {
    #[cfg(desktop)]
    {
        session::stop().await
    }
    #[cfg(not(desktop))]
    {
        Ok("No active session".to_string())
    }
}

/// Screens, or windows, in the order their indexes refer to. A share or a
/// thumbnail asked for by index means the source at that index in the list
/// most recently returned here.
pub fn list_capture_sources(capture_full_screen: bool) -> Vec<CaptureSource> {
    #[cfg(desktop)]
    {
        sources::list(capture_full_screen)
    }
    #[cfg(not(desktop))]
    {
        let _ = capture_full_screen;
        Vec::new()
    }
}

/// A small JPEG preview of one source, at most 320 px wide. Windows only so
/// far; elsewhere `None`, which the picker renders as a plain tile.
pub fn get_capture_source_thumbnail(
    capture_full_screen: bool,
    source_index: u32,
) -> Option<Vec<u8>> {
    #[cfg(target_os = "windows")]
    {
        thumbnail::capture(capture_full_screen, source_index)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (capture_full_screen, source_index);
        None
    }
}

/// Applications currently playing audio, for Linux window-capture audio.
/// Empty elsewhere: Windows chooses by the window's process id instead.
pub fn list_audio_sources() -> Vec<AudioSource> {
    #[cfg(desktop)]
    {
        audio::list_sources()
    }
    #[cfg(not(desktop))]
    {
        Vec::new()
    }
}
