//! A share's threads and GPU work ahead of a game's, on Windows.
//!
//! Windows runs a game's GPU work and threads ahead of a background process's
//! at the same priority, and Rift is a background process while the game it
//! shares is in front. Its capture, the conversion draw and NVENC's submit
//! then wait their turn: a friend's share beside a game logged NVENC's send
//! at 5 to 7 ms a picture but up to 86 ms at worst, five pictures' time, and
//! a heavier game took the share to a fraction of its rate (Nov 18 2026
//! review, A4). OBS and Sunshine raise the same things for the same reason.
//!
//! Each step is asked for and its refusal logged, never acted on: raising the
//! GPU's priority past normal needs a privilege an ordinary user may not
//! hold, and a share runs just as before without it.

/// Raise the calling thread above normal: the share's capture, conversion
/// and encoder threads, which a game's own threads otherwise crowd out.
pub(crate) fn raise_this_thread() {
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::System::Threading::{
            GetCurrentThread, SetThreadPriority, THREAD_PRIORITY_ABOVE_NORMAL,
        };
        // SAFETY: the pseudo-handle of the calling thread.
        if let Err(e) =
            unsafe { SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL) }
        {
            log::info!(
                "share: thread {:?} left at normal priority: {e}",
                std::thread::current().name()
            );
        }
    }
}

/// The GPU scheduling priority class of the whole process, which every
/// device in it takes: Rift's own, FFmpeg's encoder's and libwebrtc's DXGI
/// duplication's alike.
#[cfg(target_os = "windows")]
mod process_class {
    use windows::Win32::Foundation::HANDLE;

    /// `D3DKMT_SCHEDULINGPRIORITYCLASS`: normal, and high, which Sunshine
    /// uses. Realtime can starve the desktop's own compositor.
    pub(super) const NORMAL: i32 = 2;
    pub(super) const HIGH: i32 = 4;

    #[link(name = "gdi32")]
    extern "system" {
        // In gdi32 on every Windows Rift runs on (from Vista); declared here
        // rather than taking the Windows Driver Kit's bindings for one call.
        fn D3DKMTSetProcessSchedulingPriorityClass(process: HANDLE, priority: i32) -> i32;
    }

    /// Set the class, or say why not as an NTSTATUS.
    pub(super) fn set(priority: i32) -> Result<(), i32> {
        // SAFETY: the pseudo-handle of this process and a valid class.
        let status = unsafe {
            D3DKMTSetProcessSchedulingPriorityClass(
                windows::Win32::System::Threading::GetCurrentProcess(),
                priority,
            )
        };
        if status >= 0 {
            Ok(())
        } else {
            Err(status)
        }
    }
}

/// Holds the process's GPU work at high priority while a share runs, and puts
/// it back to normal when the last holder drops: a share handing over from
/// libwebrtc's capture to Rift's holds one in each for a moment.
#[cfg(target_os = "windows")]
pub(crate) struct GpuPriority(());

/// How many hold the priority, and whether raising it worked.
#[cfg(target_os = "windows")]
static HOLDERS: std::sync::Mutex<(u32, bool)> = std::sync::Mutex::new((0, false));

#[cfg(target_os = "windows")]
impl GpuPriority {
    pub(crate) fn raise() -> GpuPriority {
        let mut holders = HOLDERS.lock().unwrap_or_else(|e| e.into_inner());
        if holders.0 == 0 {
            holders.1 = match process_class::set(process_class::HIGH) {
                Ok(()) => {
                    log::info!("share: GPU work at high priority");
                    true
                }
                Err(status) => {
                    log::info!(
                        "share: GPU work left at normal priority (NTSTATUS {:#010x})",
                        status as u32
                    );
                    false
                }
            };
        }
        holders.0 += 1;
        GpuPriority(())
    }
}

#[cfg(target_os = "windows")]
impl Drop for GpuPriority {
    fn drop(&mut self) {
        let mut holders = HOLDERS.lock().unwrap_or_else(|e| e.into_inner());
        holders.0 = holders.0.saturating_sub(1);
        if holders.0 == 0 && std::mem::take(&mut holders.1) {
            if let Err(status) = process_class::set(process_class::NORMAL) {
                log::info!(
                    "share: GPU priority not handed back (NTSTATUS {:#010x})",
                    status as u32
                );
            }
        }
    }
}
