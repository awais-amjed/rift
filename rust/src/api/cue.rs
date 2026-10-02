//! Rift's own sounds on the chosen output device.
//!
//! The app's audio player has no way to pick a device on the desktop: it
//! plays on whatever the system default is, so with a headset chosen in
//! settings the ring still came out of the speakers. A call's audio goes where
//! it is told because WebRTC opens the device itself; on Windows and Linux the
//! cues now do the same, opening the device the call would.

#[cfg(any(target_os = "windows", target_os = "linux"))]
use crate::cue;

/// A cue that is playing: what to stop or turn, and how long one pass lasts,
/// since the player does not say when it has finished.
pub struct CueStarted {
    pub id: u32,
    pub duration_ms: u32,
}

/// Plays `mp3` on `device_id` — the id WebRTC lists the output under (the
/// endpoint id on Windows, the sink's description on Linux), or `None` for
/// the default — at `volume` (0 to 1), once or over and over. Answers once the
/// device has opened, or with why it would not, so the caller can fall back to
/// the default device.
///
/// Off Windows and Linux it always fails, and the caller keeps its own player.
pub fn play_cue(
    device_id: Option<String>,
    mp3: Vec<u8>,
    volume: f32,
    looping: bool,
) -> Result<CueStarted, String> {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        let cue = cue::Cue::from_mp3(&mp3, looping)?;
        let duration_ms = cue.duration_ms();
        let id = cue::play(device_id, cue, volume)?;
        Ok(CueStarted { id, duration_ms })
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    {
        let _ = (device_id, mp3, volume, looping);
        Err("Cues open the device themselves only on Windows and Linux".to_string())
    }
}

/// Turns a playing cue up or down. Nothing if it has ended.
pub fn set_cue_volume(id: u32, volume: f32) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    cue::set_volume(id, volume);
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = (id, volume);
}

/// Stops a playing cue. Nothing if it has ended.
pub fn stop_cue(id: u32) {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    cue::stop(id);
    #[cfg(not(any(target_os = "windows", target_os = "linux")))]
    let _ = id;
}
