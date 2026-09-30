//! Windows: WASAPI loopback, of one process or of the whole default output.
use super::{
    samples_from_le_bytes, AudioCapture, AudioCaptureHandle, Command, NUM_CHANNELS, SAMPLE_RATE,
};
use livekit::prelude::*;
use std::collections::HashMap;
use std::sync::mpsc::{Receiver, TryRecvError};
use std::thread::{self, JoinHandle};
use std::time::Duration;
use tokio::sync::mpsc::Sender as FrameSender;
use crate::api::screenshare::types::AudioSource;
use wasapi::{
    AudioClient, DeviceEnumerator, DeviceState, Direction, SampleType, SessionState, StreamMode,
    WaveFormat,
};
use windows::core::BOOL;
use windows::Win32::Foundation::{CloseHandle, HANDLE, HWND, LPARAM, WAIT_OBJECT_0};
use windows::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};
use windows::Win32::System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible,
};

/// Between reads. Packets are 10 ms, so this is never behind by more than
/// one of them while keeping the thread off the CPU.
const POLL: Duration = Duration::from_millis(5);
/// One second, in the 100 ns units WASAPI counts in.
const BUFFER_DURATION_HNS: i64 = 10_000_000;
const READ_BUFFER_BYTES: usize = 16 * 1024;

pub(crate) async fn start(room: &Room, request: AudioCapture) -> Option<AudioCaptureHandle> {
    let pid = request.selection.pid;
    match pid {
        Some(pid) => log::info!("audio: capturing process {pid}"),
        None => log::info!("audio: capturing the default output"),
    }
    super::publish_and_feed(
        room,
        Box::new(move |commands, frames| spawn_capture_thread(pid, commands, frames)),
        &request.track_name,
        request.on_ended,
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
        let Some(mut client) = open_client(pid) else {
            return;
        };
        let Some(capture) = start_capture(&mut client) else {
            return;
        };
        let process = pid.and_then(ProcessWatch::open);

        let mut buffer = vec![0u8; READ_BUFFER_BYTES];
        loop {
            match commands.try_recv() {
                Ok(Command::Terminate) | Err(TryRecvError::Disconnected) => break,
                Err(TryRecvError::Empty) => {}
            }
            // A process loopback stream outlives the process: once it quits,
            // reads just come back empty, for good. Leaving is what tells the
            // feed task the source went away, as a closed stream does on Linux.
            if process.as_ref().is_some_and(ProcessWatch::has_exited) {
                log::info!("audio: the captured process exited");
                break;
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

/// A handle kept on the process being captured, to notice it quitting.
struct ProcessWatch(HANDLE);

impl ProcessWatch {
    /// `None` when the process cannot be opened — then the share simply does
    /// not end by itself, which is how it behaved before this existed.
    fn open(pid: u32) -> Option<Self> {
        // SAFETY: a plain handle request; the handle is closed on drop.
        unsafe { OpenProcess(PROCESS_SYNCHRONIZE, false, pid) }
            .ok()
            .map(Self)
    }

    fn has_exited(&self) -> bool {
        // SAFETY: the handle is open for as long as `self` is. A zero timeout
        // only asks, it never waits.
        unsafe { WaitForSingleObject(self.0, 0) == WAIT_OBJECT_0 }
    }
}

impl Drop for ProcessWatch {
    fn drop(&mut self) {
        // SAFETY: opened in `open` and closed exactly once, here.
        let _ = unsafe { CloseHandle(self.0) };
    }
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

fn start_capture(client: &mut AudioClient) -> Option<wasapi::AudioCaptureClient> {
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

/// Applications playing sound right now: one entry per process with an
/// active audio session on any output, for the sound share's picker.
///
/// Windows has no sink inputs to list, so the entry's `index` carries the
/// **process id** — the thing a Windows capture is opened by — and `sink` is
/// always 0. Rift itself is left out: its session is the call, and offering
/// the call back into the call is an echo. So is the system-sounds session
/// (process 0), which belongs to nobody.
///
/// Only *active* sessions count. An application that opened a stream and is
/// not playing into it is not something anyone means by "what's playing",
/// and the picker's empty state already says to start something first.
pub(crate) fn list_sources() -> Vec<AudioSource> {
    // As for the endpoint list: whichever apartment this thread already has
    // serves, so the answer is deliberately not checked.
    let _ = wasapi::initialize_mta().ok();

    let collection = match DeviceEnumerator::new()
        .and_then(|enumerator| enumerator.get_device_collection(&Direction::Render))
    {
        Ok(collection) => collection,
        Err(e) => {
            log::warn!("audio: no output devices to list sessions on: {e:?}");
            return Vec::new();
        }
    };

    let own = std::process::id();
    let mut pids = Vec::new();
    for index in 0..collection.get_nbr_devices().unwrap_or(0) {
        let Ok(device) = collection.get_device_at_index(index) else {
            continue;
        };
        if !matches!(device.get_state(), Ok(DeviceState::Active)) {
            continue;
        }
        let Ok(sessions) = device
            .get_iaudiosessionmanager()
            .and_then(|manager| manager.get_audiosessionenumerator())
        else {
            continue;
        };
        for session in 0..sessions.get_count().unwrap_or(0) {
            let Ok(session) = sessions.get_session(session) else {
                continue;
            };
            if !matches!(session.get_state(), Ok(SessionState::Active)) {
                continue;
            }
            match session.get_process_id() {
                Ok(pid) if pid != 0 && pid != own => pids.push(pid),
                _ => {}
            }
        }
    }
    // The same application on two outputs is still one choice.
    pids.sort_unstable();
    pids.dedup();

    let windows = list_windows();
    let executables = executable_names();
    let mut sources: Vec<AudioSource> = pids
        .into_iter()
        .map(|pid| {
            let (app_name, binary) = executables
                .get(&pid)
                .map(|file| names_from_image_path(file))
                .unwrap_or_default();
            // A player's window title usually names what it is playing. A
            // browser plays from a helper process with no window, and then
            // there is simply no subtitle.
            let media_name = windows
                .iter()
                .find(|(_, window_pid)| *window_pid == pid)
                .map(|(title, _)| title.clone())
                .unwrap_or_default();
            AudioSource {
                index: pid,
                sink: 0,
                app_name,
                binary,
                media_name,
            }
        })
        .collect();
    sources.sort_by_key(|source| source.app_name.to_lowercase());
    sources
}

/// Every running process's executable file name, by process id.
///
/// From a process snapshot rather than by opening each process: opening one
/// that runs with more rights than Rift — a remote-desktop service, anything
/// started as administrator — is refused, and its entry came out as "Unknown
/// application". The snapshot names every process without asking any of them.
fn executable_names() -> HashMap<u32, String> {
    let mut names = HashMap::new();
    // SAFETY: the snapshot handle is closed before returning, and `entry`
    // carries its own size as the API requires.
    unsafe {
        let Ok(snapshot) = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) else {
            return names;
        };
        let mut entry = PROCESSENTRY32W {
            dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32,
            ..Default::default()
        };
        let mut more = Process32FirstW(snapshot, &mut entry).is_ok();
        while more {
            let length = entry
                .szExeFile
                .iter()
                .position(|&unit| unit == 0)
                .unwrap_or(entry.szExeFile.len());
            names.insert(
                entry.th32ProcessID,
                String::from_utf16_lossy(&entry.szExeFile[..length]),
            );
            more = Process32NextW(snapshot, &mut entry).is_ok();
        }
        let _ = CloseHandle(snapshot);
    }
    names
}

/// `(name, file name)` from an executable's path or file name —
/// `("chrome", "chrome.exe")` — the same pair a PulseAudio stream offers as its application name and
/// binary.
fn names_from_image_path(path: &str) -> (String, String) {
    let binary = path.rsplit(['\\', '/']).next().unwrap_or(path).to_string();
    let name = match binary.rsplit_once('.') {
        Some((stem, _)) if !stem.is_empty() => stem.to_string(),
        _ => binary.clone(),
    };
    (name, binary)
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

#[cfg(test)]
mod tests {
    use super::names_from_image_path;

    #[test]
    fn an_executable_path_gives_its_name_and_file() {
        assert_eq!(
            names_from_image_path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
            ("chrome".to_string(), "chrome.exe".to_string())
        );
    }

    #[test]
    fn a_name_without_an_extension_is_kept_whole() {
        assert_eq!(
            names_from_image_path(r"C:\tools\player"),
            ("player".to_string(), "player".to_string())
        );
    }

    #[test]
    fn only_the_last_extension_is_dropped() {
        assert_eq!(
            names_from_image_path(r"D:\apps\my.player.exe"),
            ("my.player".to_string(), "my.player.exe".to_string())
        );
    }
}
