/// Screenshare API for LiveKit integration
///
/// This module handles screen sharing functionality by receiving
/// configuration from Flutter and managing the LiveKit session.

use livekit::prelude::*;
use std::sync::Mutex;

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
}

// Global state to hold the room connection
static ROOM: Mutex<Option<Room>> = Mutex::new(None);

/// Start screen sharing with the given configuration.
/// Connects to LiveKit room with the provided token.
pub async fn start_screenshare(config: ScreenShareConfig) -> Result<String, String> {
    println!("=== SCREENSHARE DATA RECEIVED IN RUST ===");
    println!("LiveKit URL: {}", config.livekit_url);
    println!("LiveKit Token: {}", config.livekit_token);
    println!("Channel ID: {}", config.channel_id);
    println!("Identity: {}", config.identity);
    println!("Display Name: {}", config.display_name);
    println!("Resolution: {}p", config.resolution);
    println!("FPS: {}", config.fps);
    println!("Bitrate: {} Mbps", config.bitrate);
    println!("Share Audio: {}", config.share_audio);
    println!("=========================================");

    // Check if already connected
    {
        let room_lock = ROOM.lock().unwrap();
        if room_lock.is_some() {
            return Err("Already connected to a room".to_string());
        }
    }

    println!("Attempting to connect to LiveKit room...");

    // Connect to LiveKit room
    match Room::connect(&config.livekit_url, &config.livekit_token, RoomOptions::default()).await {
        Ok((room, _rx)) => {
            let room_name = room.name().to_string();
            let room_sid = room.sid().await.to_string();

            println!("✓ Successfully connected to LiveKit room!");
            println!("  Room name: {}", room_name);
            println!("  Room SID: {}", room_sid);
            println!("  Identity: {}", config.identity);

            // Store the room connection
            {
                let mut room_lock = ROOM.lock().unwrap();
                *room_lock = Some(room);
            }

            Ok(format!("Connected to room: {} ({})", room_name, room_sid))
        }
        Err(e) => {
            let error_msg = format!("Failed to connect to LiveKit: {:?}", e);
            println!("✗ {}", error_msg);
            Err(error_msg)
        }
    }
}

/// Stop screen sharing and disconnect from LiveKit.
pub async fn stop_screenshare() -> Result<String, String> {
    println!("=== STOPPING SCREENSHARE IN RUST ===");

    // 1. Extract the room from the Mutex and release the lock immediately
    let room_option = {
        let mut room_lock = ROOM.lock().unwrap();
        room_lock.take()
    };

    // 2. Explicitly close the room if it exists
    if let Some(room) = room_option {
        println!("Disconnecting from LiveKit room...");

        // Tell the LiveKit engine to gracefully shut down the connection
        if let Err(e) = room.close().await {
            println!("⚠ Warning during disconnect: {:?}", e);
        }

        println!("✓ Successfully disconnected from LiveKit");
        Ok("Disconnected successfully".to_string())
    } else {
        println!("No active room connection to stop");
        Ok("No active connection".to_string())
    }
}
