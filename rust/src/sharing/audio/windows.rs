//! Windows: WASAPI loopback, of one process or of the whole default output.
use super::{
    samples_from_le_bytes, AudioCaptureHandle, AudioSelection, Command, OnEnded, NUM_CHANNELS,
    SAMPLE_RATE,
};
use livekit::prelude::*;
use std::sync::mpsc::{Receiver, TryRecvError};
use std::thread::{self, JoinHandle};
use std::time::Duration;
use tokio::sync::mpsc::Sender as FrameSender;
use wasapi::{AudioClient, DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat};
use windows::core::BOOL;
use windows::Win32::Foundation::{HWND, LPARAM};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible,
};

/// Between reads. Packets are 10 ms, so this is never behind by more than
/// one of them while keeping the thread off the CPU.
const POLL: Duration = Duration::from_millis(5);
/// One second, in the 100 ns units WASAPI counts in.
const BUFFER_DURATION_HNS: i64 = 10_000_000;
const READ_BUFFER_BYTES: usize = 16 * 1024;

pub(crate) async fn start(
    room: &Room,
    selection: AudioSelection,
    on_ended: Option<OnEnded>,
) -> Option<AudioCaptureHandle> {
    let pid = selection.pid;
    match pid {
        Some(pid) => log::info!("audio: capturing process {pid}"),
        None => log::info!("audio: capturing the default output"),
    }
    super::publish_and_feed(
        room,
        Box::new(move |commands, frames| spawn_capture_thread(pid, commands, frames)),
        on_ended,
    )
    .await
}

fn spawn_capture_thread(
    pid: Option<u32>,
    commands: Receiver<Command>,
    frames: FrameSender<Vec<i16>>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        if wasapi::initialize_mta().is_err() {
            log::warn!("audio: could not initialise COM on the capture thread");
            return;
        }
        let Some(client) = open_client(pid) else {
            return;
        };
        let Some(capture) = start_capture(&client) else {
            return;
        };

        let mut buffer = vec![0u8; READ_BUFFER_BYTES];
        loop {
            match commands.try_recv() {
                Ok(Command::Terminate) | Err(TryRecvError::Disconnected) => break,
                Err(TryRecvError::Empty) => {}
            }
            if let Ok((frame_count, _)) = capture.read_from_device(&mut buffer) {
                if frame_count > 0 {
                    let bytes = frame_count as usize * NUM_CHANNELS as usize * 2;
                    if frames
                        .blocking_send(samples_from_le_bytes(&buffer[..bytes]))
                        .is_err()
                    {
                        break;
                    }
                }
            }
            thread::sleep(POLL);
        }
        log::info!("audio: capture thread exiting");
    })
}

fn open_client(pid: Option<u32>) -> Option<AudioClient> {
    match pid {
        Some(pid) => AudioClient::new_application_loopback_client(pid, true)
            .map_err(|e| log::warn!("audio: no loopback client for process {pid}: {e:?}"))
            .ok(),
        None => {
            let device = DeviceEnumerator::new()
                .and_then(|enumerator| enumerator.get_default_device(&Direction::Render))
                .map_err(|e| log::warn!("audio: no default output device: {e:?}"))
                .ok()?;
            device
                .get_iaudioclient()
                .map_err(|e| log::warn!("audio: no client for the default output: {e:?}"))
                .ok()
        }
    }
}

fn start_capture(client: &AudioClient) -> Option<wasapi::AudioCaptureClient> {
    // 48 kHz, 16-bit integer, stereo: what LiveKit's source is created with.
    let format = WaveFormat::new(
        16,
        16,
        &SampleType::Int,
        SAMPLE_RATE as usize,
        NUM_CHANNELS as usize,
        None,
    );
    let mode = StreamMode::PollingShared {
        autoconvert: true,
        buffer_duration_hns: BUFFER_DURATION_HNS,
    };
    if let Err(e) = client.initialize_client(&format, &Direction::Capture, &mode) {
        log::warn!("audio: WASAPI client refused the format: {e:?}");
        return None;
    }
    let capture = client
        .get_audiocaptureclient()
        .map_err(|e| log::warn!("audio: no capture client: {e:?}"))
        .ok()?;
    if let Err(e) = client.start_stream() {
        log::warn!("audio: WASAPI stream would not start: {e:?}");
        return None;
    }
    Some(capture)
}

/// `(title, pid)` of every visible titled window.
pub(crate) fn list_windows() -> Vec<(String, u32)> {
    let mut windows: Vec<(String, u32)> = Vec::new();
    // SAFETY: the callback only runs during this call, and the pointer it is
    // handed is to `windows`, which outlives the call.
    unsafe {
        let _ = EnumWindows(
            Some(enum_windows_proc),
            LPARAM(&mut windows as *mut _ as isize),
        );
    }
    windows
}

unsafe extern "system" fn enum_windows_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
    if IsWindowVisible(hwnd).as_bool() {
        let length = GetWindowTextLengthW(hwnd);
        if length > 0 {
            let mut buffer = vec![0u16; (length + 1) as usize];
            GetWindowTextW(hwnd, &mut buffer);
            let title = String::from_utf16_lossy(&buffer[..length as usize]);
            let mut pid = 0u32;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            let windows = &mut *(lparam.0 as *mut Vec<(String, u32)>);
            windows.push((title, pid));
        }
    }
    BOOL::from(true)
}
