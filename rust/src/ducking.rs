//! Windows: hearing when Windows turns other apps down for a call.
//!
//! Windows lowers every other sound while an app has playback open on the
//! communications device ("ducking", 80% by default), and tells any app that
//! asks: `IAudioSessionManager2::RegisterDuckNotification` with no session
//! of its own hears every duck and unduck, with the session that caused it.
//! A session's id ends in `%b<pid>`, so Rift can tell its own call apart
//! from another app's. Measured Oct 10 2026 in the Windows 11 VM: playback
//! opened through the communications role lowered a tone by 18 dB and fired
//! one duck, and one unduck when it closed; the same speakers through the
//! console role did neither.
//!
//! The choice of what Windows does is the user's, in the Sound window's
//! Communications tab, and is stored in the registry ([preference]).
use std::sync::Mutex;

use windows::core::{implement, PCWSTR};
use windows::Win32::Media::Audio::{
    eRender, IAudioSessionManager2, IAudioVolumeDuckNotification,
    IAudioVolumeDuckNotification_Impl, IMMDeviceEnumerator, MMDeviceEnumerator,
    DEVICE_STATE_ACTIVE,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED,
};
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD};

use crate::api::ducking::DuckingEvent;
use crate::frb_generated::StreamSink;

/// Where Dart hears the events. Replaced when Dart listens again (a hot
/// restart); the listener itself is registered once per process.
static SINK: Mutex<Option<StreamSink<DuckingEvent>>> = Mutex::new(None);
static STARTED: Mutex<bool> = Mutex::new(false);

/// What Windows does to other sounds while a call is open, as the Sound
/// window's Communications tab stores it: 0 mutes them, 1 lowers them by
/// 80%, 2 by 50%, 3 does nothing. A user who never opened that tab has no
/// value at all, which Windows treats as 1.
pub(crate) fn preference() -> u32 {
    let key: Vec<u16> = "Software\\Microsoft\\Multimedia\\Audio\0"
        .encode_utf16()
        .collect();
    let name: Vec<u16> = "UserDuckingPreference\0".encode_utf16().collect();
    let mut value = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    let read = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            PCWSTR(key.as_ptr()),
            PCWSTR(name.as_ptr()),
            RRF_RT_REG_DWORD,
            None,
            Some(&mut value as *mut u32 as *mut _),
            Some(&mut size),
        )
    };
    if read.is_ok() {
        value
    } else {
        1
    }
}

/// Sends a [DuckingEvent] each time Windows lowers other apps or lets them
/// back up, until the process ends.
pub(crate) fn watch(sink: StreamSink<DuckingEvent>) -> Result<(), String> {
    *SINK.lock().unwrap_or_else(|e| e.into_inner()) = Some(sink);
    let mut started = STARTED.lock().unwrap_or_else(|e| e.into_inner());
    if *started {
        return Ok(());
    }
    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    std::thread::Builder::new()
        .name("ducking".into())
        .spawn(move || {
            // The registrations live as long as this thread, which parks for
            // the life of the process: COM calls the listener on its own
            // threads, and the objects only have to stay alive.
            let held = unsafe { register() };
            let ok = held.as_ref().map(|h| h.len()).map_err(Clone::clone);
            let _ = ready_tx.send(ok);
            if held.is_ok() {
                loop {
                    std::thread::park();
                }
            }
        })
        .map_err(|e| format!("could not start the ducking listener: {e}"))?;
    let devices = ready_rx
        .recv()
        .map_err(|_| "the ducking listener stopped".to_string())??;
    log::info!(
        "ducking: listening on {devices} output(s); Windows is set to {}",
        describe(preference())
    );
    *started = true;
    Ok(())
}

fn describe(preference: u32) -> &'static str {
    match preference {
        0 => "mute other sounds",
        2 => "lower other sounds by 50%",
        3 => "do nothing",
        _ => "lower other sounds by 80%",
    }
}

/// Registers on every active output, because a registration lives on one
/// device's session manager and dies with it: a headset unplugged mid-call
/// would take a single registration with it. Each output hears the same
/// event, so [Listener] lets the repeats go.
unsafe fn register() -> Result<Vec<(IAudioSessionManager2, IAudioVolumeDuckNotification)>, String> {
    let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
    let enumerator: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)
        .map_err(|e| format!("no device enumerator: {e}"))?;
    let devices = enumerator
        .EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)
        .map_err(|e| format!("no outputs: {e}"))?;
    let listener: IAudioVolumeDuckNotification = Listener::default().into();
    let mut held = Vec::new();
    for i in 0..devices.GetCount().unwrap_or(0) {
        let Ok(device) = devices.Item(i) else {
            continue;
        };
        let Ok(manager) = device.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else {
            continue;
        };
        if manager
            .RegisterDuckNotification(PCWSTR::null(), &listener)
            .is_ok()
        {
            held.push((manager, listener.clone()));
        }
    }
    if held.is_empty() {
        return Err("no output took the ducking listener".into());
    }
    Ok(held)
}

#[implement(IAudioVolumeDuckNotification)]
#[derive(Default)]
struct Listener {
    /// The last event passed on, so the same one heard on every output goes
    /// to Dart once.
    last: Mutex<Option<(bool, String)>>,
}

impl Listener {
    fn pass(&self, ducked: bool, session: &PCWSTR) {
        let session = unsafe { session.to_string() }.unwrap_or_default();
        {
            let mut last = self.last.lock().unwrap_or_else(|e| e.into_inner());
            if last.as_ref() == Some(&(ducked, session.clone())) {
                return;
            }
            *last = Some((ducked, session.clone()));
        }
        let (app, pid) = session_owner(&session);
        let by_rift = pid == Some(std::process::id());
        log::info!(
            "ducking: Windows {} other sounds for {app}{}",
            if ducked { "lowered" } else { "restored" },
            if by_rift { " (this call)" } else { "" },
        );
        if let Some(sink) = SINK.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
            let _ = sink.add(DuckingEvent {
                ducked,
                by_rift,
                app,
            });
        }
    }
}

impl IAudioVolumeDuckNotification_Impl for Listener_Impl {
    fn OnVolumeDuckNotification(&self, session: &PCWSTR, _calls: u32) -> windows::core::Result<()> {
        self.pass(true, session);
        Ok(())
    }

    fn OnVolumeUnduckNotification(&self, session: &PCWSTR) -> windows::core::Result<()> {
        self.pass(false, session);
        Ok(())
    }
}

/// The program's file name and process id in a session instance id, which
/// reads `{device}|\Device\HarddiskVolume3\…\app.exe%b{guid}|1%b<pid>`. The
/// name only: the path has the user's own folder in it, and goes to a log.
fn session_owner(session: &str) -> (String, Option<u32>) {
    let pid = session.rsplit("%b").next().and_then(|p| p.parse().ok());
    let app = session
        .split('|')
        .nth(1)
        .and_then(|path| path.split("%b").next())
        .and_then(|path| path.rsplit('\\').next())
        .filter(|name| !name.is_empty())
        .unwrap_or("an app")
        .to_string();
    (app, pid)
}

#[cfg(test)]
mod tests {
    use super::session_owner;

    #[test]
    fn reads_the_owner_of_a_session() {
        let id = "{0.0.0.00000000}.{2285091f-8c43-4814-846c-66ccf61b53fe}|\\Device\\HarddiskVolume3\\Users\\meow\\duckprobe\\target\\release\\duckprobe.exe%b{00000000-0000-0000-0000-000000000000}|1%b7844";
        assert_eq!(session_owner(id), ("duckprobe.exe".to_string(), Some(7844)));
        assert_eq!(session_owner("nonsense"), ("an app".to_string(), None));
    }
}
