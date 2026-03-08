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
}

#[flutter_rust_bridge::frb(ignore)]
pub static SESSION: Mutex<Option<ScreenShareSession>> = Mutex::new(None);


