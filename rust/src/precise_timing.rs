//! Windows' 1 ms timer, and running unthrottled, for as long as anything
//! holds them: a share's capture, and a call that the person asked to run
//! on it (Settings → Voice, Beta options).
//!
//! Left alone, Windows wakes a sleeping thread in steps of about 15.6 ms. A
//! share's `recv_timeout` slept in those steps, and so may the microphone's
//! wait for DPDFNet's frame ([`crate::dpdfnet`]), which has 7 ms: overslept,
//! the microphone misses its own turn, heard as crackle. Windows 11 also
//! slows a process it judges out of sight (EcoQoS) and may ignore its finer
//! clock, and both a share and a call run while a game covers Rift. In a
//! test process with no window, capture at 120 fps fell from about 106
//! pictures a second to 92 a few seconds in, and FFmpeg's Quick Sync sent
//! 88.7 fps; with throttling off, 119.8 and 118.3 (Oct 16 2026, an i7-12700H
//! laptop). Once nothing holds them, Windows decides again.
//!
//! Elsewhere a hold does nothing: Linux and macOS sleep as long as asked.

use std::sync::Mutex;

/// How many [`Precise`] are held; the first turns both on, the last off.
static HOLDS: Mutex<Holds> = Mutex::new(Holds(0));

/// Held, the timer is at 1 ms and the process runs unthrottled.
pub(crate) struct Precise(());

impl Precise {
    pub(crate) fn hold() -> Precise {
        if HOLDS.lock().map(|mut holds| holds.take()).unwrap_or(false) {
            on();
        }
        Precise(())
    }
}

impl Drop for Precise {
    fn drop(&mut self) {
        if HOLDS.lock().map(|mut holds| holds.give()).unwrap_or(false) {
            off();
        }
    }
}

/// A call's hold, while settings ask for one and a call is on.
static CALL: Mutex<Option<Precise>> = Mutex::new(None);

/// Holds [`Precise`] for the call while `hold`, and gives it back after.
pub(crate) fn hold_for_call(hold: bool) {
    if let Ok(mut call) = CALL.lock() {
        if hold {
            call.get_or_insert_with(Precise::hold);
        } else {
            *call = None;
        }
    }
}

struct Holds(u32);

impl Holds {
    /// True for the first hold.
    fn take(&mut self) -> bool {
        self.0 += 1;
        self.0 == 1
    }

    /// True for the last one given back.
    fn give(&mut self) -> bool {
        self.0 = self.0.saturating_sub(1);
        self.0 == 0
    }
}

#[cfg(target_os = "windows")]
fn on() {
    use windows::Win32::System::Threading::{
        PROCESS_POWER_THROTTLING_EXECUTION_SPEED, PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION,
    };
    // Execution speed and the timer resolution both held unthrottled.
    set_power_throttling(
        PROCESS_POWER_THROTTLING_EXECUTION_SPEED | PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION,
    );
    // SAFETY: no pointers; paired with the timeEndPeriod in `off`.
    unsafe { windows::Win32::Media::timeBeginPeriod(1) };
}

#[cfg(target_os = "windows")]
fn off() {
    // SAFETY: no pointers; pairs the timeBeginPeriod in `on`.
    unsafe { windows::Win32::Media::timeEndPeriod(1) };
    set_power_throttling(0);
}

#[cfg(not(target_os = "windows"))]
fn on() {}

#[cfg(not(target_os = "windows"))]
fn off() {}

/// Turn off Windows' power throttling for this process in the ways `held`
/// names, leaving the rest to Windows: 0 hands all of it back.
#[cfg(target_os = "windows")]
fn set_power_throttling(held: u32) {
    use windows::Win32::System::Threading::{
        GetCurrentProcess, ProcessPowerThrottling, SetProcessInformation,
        PROCESS_POWER_THROTTLING_CURRENT_VERSION, PROCESS_POWER_THROTTLING_STATE,
    };
    let state = PROCESS_POWER_THROTTLING_STATE {
        Version: PROCESS_POWER_THROTTLING_CURRENT_VERSION,
        ControlMask: held,
        StateMask: 0,
    };
    // SAFETY: `state` is the structure this information class takes, and
    // outlives the call.
    let set = unsafe {
        SetProcessInformation(
            GetCurrentProcess(),
            ProcessPowerThrottling,
            std::ptr::from_ref(&state).cast(),
            std::mem::size_of::<PROCESS_POWER_THROTTLING_STATE>() as u32,
        )
    };
    if let Err(e) = set {
        log::info!("timing: power throttling left to Windows: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_first_hold_and_the_last_release_switch() {
        let mut holds = Holds(0);
        assert!(holds.take());
        assert!(!holds.take());
        assert!(!holds.give());
        assert!(holds.give());
        assert!(holds.take());
    }
}
