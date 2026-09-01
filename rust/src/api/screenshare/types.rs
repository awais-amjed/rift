//! Types shared across the screenshare module.
//!
//! [`ScreenShareConfig`] and [`CaptureSource`] cross the bridge and so exist
//! everywhere. The session below holds a live LiveKit `Room` and a capture
//! thread, neither of which has a meaning off the desktop — see the desktop
//! dependency note in Cargo.toml.
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use livekit::prelude::*;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use std::sync::mpsc::Sender;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use std::sync::Mutex;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use std::thread;

pub struct ScreenShareConfig {
    pub livekit_url: String,
    pub livekit_token: String,
    pub channel_id: String,
    pub identity: String,
    pub display_name: String,
    pub resolution: i32,
    pub fps: i32,
    pub bitrate: i32,
    pub share_audio: bool,
    pub capture_full_screen: bool,
    /// Selected desktop capture source index from `list_capture_sources`.
    pub selected_video_source_index: Option<u32>,
    /// Video codec to use: "H264", "VP8", "VP9", or "AV1"
    pub codec: String,
    /// Selected audio source sink-input index (Linux PulseAudio)
    pub selected_audio_source_index: Option<u32>,
    /// Selected audio source sink index (Linux PulseAudio)
    pub selected_audio_source_sink: Option<u32>,
    /// Selected audio source process ID (Windows WASAPI)
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

/// Represents a desktop capture source (screen or window).
#[derive(Clone, Debug)]
pub struct CaptureSource {
    pub index: u32,
    pub title: String,
    /// Windows-only PID used for automatic app-loopback audio capture.
    pub audio_source_pid: Option<u32>,
}

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
#[flutter_rust_bridge::frb(ignore)]
pub enum CaptureCommand {
    Terminate,
}

// Global state to hold the room connection and capture thread
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
#[flutter_rust_bridge::frb(ignore)]
pub struct ScreenShareSession {
    pub room: Room,
    pub capture_tx: Sender<CaptureCommand>,
    pub capture_handle: thread::JoinHandle<()>,
    #[cfg(target_os = "linux")]
    pub audio_handle: Option<super::audio_linux::AudioCaptureHandle>,
    #[cfg(target_os = "windows")]
    pub audio_handle: Option<super::audio_windows::AudioCaptureHandle>,
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    pub audio_handle: Option<()>,
}

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
#[flutter_rust_bridge::frb(ignore)]
pub static SESSION: Mutex<Option<ScreenShareSession>> = Mutex::new(None);
