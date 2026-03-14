//! Windows audio enumeration and capture for screenshare
//!
//! This module provides WASAPI-based audio capture functionality via application loopback.

#[cfg(target_os = "windows")]
use wasapi::{AudioClient, Direction, SampleType, StreamMode, WaveFormat};

#[cfg(target_os = "windows")]
use windows::Win32::Foundation::{HWND, LPARAM};
#[cfg(target_os = "windows")]
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible,
};
#[cfg(target_os = "windows")]
use windows::core::BOOL;

#[cfg(target_os = "windows")]
use livekit::options::TrackPublishOptions;
use livekit::prelude::*;
#[cfg(target_os = "windows")]
use livekit::track::{LocalAudioTrack, LocalTrack, TrackSource};
#[cfg(target_os = "windows")]
use livekit::webrtc::audio_frame::AudioFrame;
#[cfg(target_os = "windows")]
use livekit::webrtc::audio_source::native::NativeAudioSource;
#[cfg(target_os = "windows")]
use livekit::webrtc::audio_source::{AudioSourceOptions, RtcAudioSource};

use std::sync::mpsc::Sender;
#[cfg(target_os = "windows")]
use std::sync::mpsc::{self, Receiver};
use std::thread::JoinHandle;
#[cfg(target_os = "windows")]
use std::thread;
use tokio::task::JoinHandle as TokioJoinHandle;

#[cfg(target_os = "windows")]
use std::time::Duration;

#[allow(dead_code)]
const SAMPLE_RATE: u32 = 48000;
#[allow(dead_code)]
const NUM_CHANNELS: u32 = 2;

/// Represents an audio source (visible window) that can be captured on Windows.
#[derive(Clone, Debug)]
pub struct AudioSourceWindows {
    pub title: String,
    pub pid: u32,
}

pub enum AudioCaptureCommand {
    Terminate,
}

/// Handle for managing Windows audio capture lifecycle.
#[flutter_rust_bridge::frb(ignore)]
pub struct AudioCaptureHandle {
    command_tx: Sender<AudioCaptureCommand>,
    capture_thread: JoinHandle<()>,
    feed_task: TokioJoinHandle<()>,
}

impl AudioCaptureHandle {
    /// Gracefully terminate audio capture.
    pub fn terminate(self) {
        let _ = self.command_tx.send(AudioCaptureCommand::Terminate);
        self.feed_task.abort();
        if let Err(err) = self.capture_thread.join() {
            println!("Windows audio capture thread join error: {:?}", err);
        }
    }
}

/// List all visible windows that can be used as audio sources on Windows.
#[cfg(target_os = "windows")]
pub fn list_audio_sources_windows() -> Vec<AudioSourceWindows> {
    let mut windows_list: Vec<AudioSourceWindows> = Vec::new();
    unsafe {
        let _ = EnumWindows(
            Some(enum_windows_proc),
            LPARAM(&mut windows_list as *mut _ as isize),
        );
    }
    windows_list
}

#[cfg(target_os = "windows")]
unsafe extern "system" fn enum_windows_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
    if IsWindowVisible(hwnd).as_bool() {
        let length = GetWindowTextLengthW(hwnd);
        if length > 0 {
            let mut buffer = vec![0u16; (length + 1) as usize];
            GetWindowTextW(hwnd, &mut buffer);
            let title = String::from_utf16_lossy(&buffer[..length as usize]);

            let mut pid = 0u32;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));

            let windows_list = &mut *(lparam.0 as *mut Vec<AudioSourceWindows>);
            windows_list.push(AudioSourceWindows { title, pid });
        }
    }
    BOOL::from(true)
}

#[cfg(not(target_os = "windows"))]
pub fn list_audio_sources_windows() -> Vec<AudioSourceWindows> {
    Vec::new()
}

/// Spawn the WASAPI loopback capture thread for a specific PID.
#[cfg(target_os = "windows")]
fn spawn_audio_capture_thread(
    pid: Option<u32>,
    command_rx: Receiver<AudioCaptureCommand>,
) -> (JoinHandle<()>, mpsc::Receiver<Vec<i16>>) {
    let (frame_tx, frame_rx) = mpsc::channel::<Vec<i16>>();

    let handle = thread::spawn(move || {
        wasapi::initialize_mta().ok().expect("Failed to initialize COM");

        // 48kHz, 16-bit Integer, Stereo - matches LiveKit's expected format
        let format = WaveFormat::new(
            16,
            16,
            &SampleType::Int,
            SAMPLE_RATE as usize,
            NUM_CHANNELS as usize,
            None,
        );

        let target_pid = pid.unwrap_or(0);
        let mut client = match AudioClient::new_application_loopback_client(target_pid, true) {
            Ok(c) => c,
            Err(e) => {
                println!(
                    "Failed to create WASAPI loopback client for PID {}: {:?}",
                    target_pid, e
                );
                return;
            }
        };

        let stream_mode = StreamMode::PollingShared {
            autoconvert: true,
            buffer_duration_hns: 10_000_000,
        };

        if let Err(e) = client.initialize_client(&format, &Direction::Capture, &stream_mode) {
            println!("Failed to initialize WASAPI client: {:?}", e);
            return;
        }

        let capture_client = match client.get_audiocaptureclient() {
            Ok(c) => c,
            Err(e) => {
                println!("Failed to get WASAPI capture client: {:?}", e);
                return;
            }
        };

        if let Err(e) = client.start_stream() {
            println!("Failed to start WASAPI stream: {:?}", e);
            return;
        }

        if let Some(value) = pid {
            println!("✓ WASAPI loopback capture started for PID: {}", value);
        } else {
            println!("✓ WASAPI system loopback capture started");
        }

        let mut audio_buffer = vec![0u8; 1024 * 16];

        loop {
            if let Ok(AudioCaptureCommand::Terminate) = command_rx.try_recv() {
                println!("Windows audio capture thread received terminate");
                break;
            }

            if let Ok((frames, _info)) = capture_client.read_from_device(&mut audio_buffer) {
                if frames > 0 {
                    // Cast raw bytes (u8) to i16 - safe because we requested 16-bit int format
                    let data_i16: &[i16] = unsafe {
                        std::slice::from_raw_parts(
                            audio_buffer.as_ptr() as *const i16,
                            (frames as usize) * NUM_CHANNELS as usize,
                        )
                    };

                    if frame_tx.send(data_i16.to_vec()).is_err() {
                        println!("Audio frame receiver disconnected, stopping capture");
                        break;
                    }
                }
            }

            // Yield thread to avoid spinning at 100% CPU
            thread::sleep(Duration::from_millis(5));
        }
    });

    (handle, frame_rx)
}

/// Start audio capture for Windows (WASAPI application loopback).
#[flutter_rust_bridge::frb(ignore)]
#[cfg(target_os = "windows")]
pub async fn start_audio_capture(
    room: &Room,
    pid: Option<u32>,
) -> Option<AudioCaptureHandle> {
    println!("Starting Windows audio capture for PID: {:?}", pid);

    let audio_source = NativeAudioSource::new(
        AudioSourceOptions::default(),
        SAMPLE_RATE,
        NUM_CHANNELS,
        100,
    );

    let audio_track = LocalAudioTrack::create_audio_track(
        "screen_share_audio",
        RtcAudioSource::Native(audio_source.clone()),
    );

    room.local_participant()
        .publish_track(
            LocalTrack::Audio(audio_track),
            TrackPublishOptions {
                source: TrackSource::ScreenshareAudio,
                ..Default::default()
            },
        )
        .await
        .ok()?;

    println!("✓ Audio track published to LiveKit");

    let (audio_cmd_tx, audio_cmd_rx) = mpsc::channel();
    let (audio_thread_handle, frame_rx) = spawn_audio_capture_thread(pid, audio_cmd_rx);

    // Bridge from std::sync::mpsc to tokio::sync::mpsc
    let (async_tx, mut async_rx) = tokio::sync::mpsc::channel::<Vec<i16>>(100);
    std::thread::spawn(move || loop {
        match frame_rx.recv() {
            Ok(samples) => {
                if async_tx.blocking_send(samples).is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    });

    // LiveKit sender task
    let audio_feed_task = tokio::spawn(async move {
        let samples_per_channel = SAMPLE_RATE / 100;
        while let Some(samples) = async_rx.recv().await {
            let frame = AudioFrame {
                data: samples.as_slice().into(),
                sample_rate: SAMPLE_RATE,
                num_channels: NUM_CHANNELS,
                samples_per_channel,
            };
            if let Err(e) = audio_source.capture_frame(&frame).await {
                println!("Failed to capture Windows audio frame: {}", e);
            }
        }
    });

    Some(AudioCaptureHandle {
        command_tx: audio_cmd_tx,
        capture_thread: audio_thread_handle,
        feed_task: audio_feed_task,
    })
}

#[flutter_rust_bridge::frb(ignore)]
#[cfg(not(target_os = "windows"))]
pub async fn start_audio_capture(
    _room: &Room,
    _pid: Option<u32>,
) -> Option<AudioCaptureHandle> {
    None
}





