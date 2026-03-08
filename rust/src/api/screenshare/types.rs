/// Types shared across the screenshare module

use livekit::prelude::*;
use std::sync::mpsc::Sender;
use std::sync::Mutex;
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
    /// Video codec to use: "H264", "VP8", "VP9", or "AV1"
    pub codec: String,
    /// Selected audio source sink-input index (Linux PulseAudio)
    pub selected_audio_source_index: Option<u32>,
    /// Selected audio source sink index (Linux PulseAudio)
    pub selected_audio_source_sink: Option<u32>,
}

#[flutter_rust_bridge::frb(ignore)]
pub enum CaptureCommand {
    Terminate,
}

// Global state to hold the room connection and capture thread
#[flutter_rust_bridge::frb(ignore)]
pub struct ScreenShareSession {
    pub room: Room,
    pub capture_tx: Sender<CaptureCommand>,
    pub capture_handle: thread::JoinHandle<()>,
    #[cfg(target_os = "linux")]
    pub audio_handle: Option<super::audio_linux::AudioCaptureHandle>,
    #[cfg(not(target_os = "linux"))]
    pub audio_handle: Option<()>,
}

#[flutter_rust_bridge::frb(ignore)]
pub static SESSION: Mutex<Option<ScreenShareSession>> = Mutex::new(None);


