//! Windows: asking the window manager about a window source directly. A
//! window source's id is its `HWND`, so these need nothing from libwebrtc.
use windows::core::BOOL;
use windows::Win32::Foundation::{HWND, LPARAM};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindow, GetWindowLongW, GetWindowTextLengthW, GetWindowTextW,
    GetWindowThreadProcessId, IsIconic, IsWindow, IsWindowVisible, GWL_EXSTYLE, GW_OWNER,
    WS_EX_APPWINDOW, WS_EX_TOOLWINDOW,
};

fn hwnd(id: u64) -> HWND {
    HWND(id as usize as *mut _)
}

/// Whether the window is minimised.
pub(crate) fn minimised(id: u64) -> bool {
    unsafe { IsIconic(hwnd(id)) }.as_bool()
}

/// Whether the window has been closed.
///
/// libwebrtc's Windows capturer does not report a closed window as a
/// permanent error — it keeps answering with the last frame it had, so the
/// share stayed up with a frozen picture and the watchers were never told
/// (measured Sep 30 2026).
pub(crate) fn closed(id: u64) -> bool {
    !unsafe { IsWindow(Some(hwnd(id))) }.as_bool()
}

/// The process that owns the window, for capturing its sound.
pub(crate) fn pid(id: u64) -> Option<u32> {
    let mut pid = 0u32;
    unsafe { GetWindowThreadProcessId(hwnd(id), Some(&mut pid)) };
    (pid != 0).then_some(pid)
}

/// `(id, title)` of every minimised window someone would recognise as an
/// app: the ones on the taskbar.
///
/// libwebrtc lists only windows it can take a picture of right now, which
/// leaves out a minimised one — and a minimised game is exactly what people
/// go looking for (reported Oct 4 2026). The rules are the capturer's own
/// for the rest: titled, visible, not owned by another window unless it
/// asks to be on the taskbar, not on another virtual desktop, and not Rift.
pub(crate) fn list_minimised() -> Vec<(u64, String)> {
    let mut found: Vec<(u64, String)> = Vec::new();
    // SAFETY: the callback only runs during this call, and the pointer it is
    // handed is to `found`, which outlives the call.
    unsafe {
        let _ = EnumWindows(
            Some(collect_minimised),
            LPARAM(&mut found as *mut _ as isize),
        );
    }
    found
}

unsafe extern "system" fn collect_minimised(window: HWND, lparam: LPARAM) -> BOOL {
    if IsIconic(window).as_bool() && IsWindowVisible(window).as_bool() && on_taskbar(window) {
        let id = window.0 as usize as u64;
        let own = pid(id) == Some(std::process::id());
        let length = GetWindowTextLengthW(window);
        if !own && length > 0 && !cloaked(window) {
            let mut buffer = vec![0u16; (length + 1) as usize];
            GetWindowTextW(window, &mut buffer);
            let title = String::from_utf16_lossy(&buffer[..length as usize]);
            let found = &mut *(lparam.0 as *mut Vec<(u64, String)>);
            found.push((id, title));
        }
    }
    BOOL::from(true)
}

unsafe fn on_taskbar(window: HWND) -> bool {
    let style = GetWindowLongW(window, GWL_EXSTYLE) as u32;
    if style & WS_EX_TOOLWINDOW.0 != 0 {
        return false;
    }
    let owned = GetWindow(window, GW_OWNER).is_ok_and(|owner| !owner.is_invalid());
    !owned || style & WS_EX_APPWINDOW.0 != 0
}

/// On another virtual desktop, or one of the hidden shells UWP apps keep.
unsafe fn cloaked(window: HWND) -> bool {
    let mut cloaked = 0u32;
    DwmGetWindowAttribute(
        window,
        DWMWA_CLOAKED,
        &mut cloaked as *mut u32 as *mut _,
        std::mem::size_of::<u32>() as u32,
    )
    .is_ok()
        && cloaked != 0
}
