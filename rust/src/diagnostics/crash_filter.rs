//! Windows: a crash nothing handled, written into the log as it happens.
//!
//! Windows' own record of a crash ([super::windows]) names only the module the
//! faulting instruction was in. For a friend's H264 share (Oct 23 2026) that
//! was `memset` in `ucrtbase.dll`, which says the bytes were bad but not who
//! wrote them. So the process's last-chance filter writes the exception and
//! the stack, each frame a module and an offset, unwinding from the context
//! the exception saved with the unwind tables every x64 module carries,
//! MinGW's FFmpeg included. Then it hands the exception to the filter that was
//! there before, or to Windows, which ends the process and records it as it
//! did.
//!
//! Only crashes reach it: an exception something handles never gets this far,
//! and a fast fail (`__fastfail`, a stack cookie) skips it altogether.
use std::fmt::Write;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use windows::core::PCWSTR;
use windows::Win32::Foundation::{EXCEPTION_ACCESS_VIOLATION, HMODULE};
use windows::Win32::System::Diagnostics::Debug::{
    SetUnhandledExceptionFilter, EXCEPTION_POINTERS, LPTOP_LEVEL_EXCEPTION_FILTER,
};
use windows::Win32::System::LibraryLoader::{
    GetModuleFileNameW, GetModuleHandleExW, GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
    GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
};
use windows::Win32::System::Threading::GetCurrentThreadId;

use super::crash_line::Line;

/// Frames written after the faulting one.
#[cfg(target_arch = "x86_64")]
const FRAMES: usize = 32;

/// `EXCEPTION_CONTINUE_SEARCH`: on to Windows' own handling.
const CONTINUE_SEARCH: i32 = 0;

/// The filter that was there before, as a function's address (0 for none).
static PREVIOUS: AtomicUsize = AtomicUsize::new(0);
static INSTALLED: AtomicBool = AtomicBool::new(false);
/// Set by the first crash written, so two threads crashing together do not
/// interleave their lines.
static HANDLING: AtomicBool = AtomicBool::new(false);

/// Puts the filter in place. Once per process.
pub(crate) fn install() {
    if INSTALLED.swap(true, Ordering::AcqRel) {
        return;
    }
    // SAFETY: replaces the process's filter, keeping the one before.
    let previous = unsafe { SetUnhandledExceptionFilter(Some(on_crash)) };
    PREVIOUS.store(previous.map_or(0, |f| f as usize), Ordering::Release);
}

unsafe extern "system" fn on_crash(info: *const EXCEPTION_POINTERS) -> i32 {
    if !info.is_null() && !HANDLING.swap(true, Ordering::AcqRel) {
        write_crash(&*info);
    }
    match PREVIOUS.load(Ordering::Acquire) {
        0 => CONTINUE_SEARCH,
        previous => {
            let previous: LPTOP_LEVEL_EXCEPTION_FILTER = std::mem::transmute(previous);
            previous.map_or(CONTINUE_SEARCH, |f| f(info))
        }
    }
}

/// # Safety
/// From the filter only, with the pointers Windows gave it.
unsafe fn write_crash(info: &EXCEPTION_POINTERS) {
    let mut line = Line::start();
    if let Some(record) = info.ExceptionRecord.as_ref() {
        let _ = write!(line, "exception {:#010x}", record.ExceptionCode.0 as u32);
        if record.ExceptionCode == EXCEPTION_ACCESS_VIOLATION && record.NumberParameters >= 2 {
            let what = match record.ExceptionInformation[0] {
                0 => "reading",
                1 => "writing",
                8 => "running",
                _ => "touching",
            };
            let _ = write!(line, " ({what} {:#x})", record.ExceptionInformation[1]);
        }
        let _ = write!(line, " on thread {}", GetCurrentThreadId());
        line.end();
        let mut line = Line::start();
        line.text("  at ");
        frame(&mut line, record.ExceptionAddress as usize);
        line.end();
    } else {
        line.text("exception, no record");
        line.end();
    }
    #[cfg(target_arch = "x86_64")]
    if let Some(context) = info.ContextRecord.as_ref() {
        unwind(context.clone());
    }
}

/// Walks the stack from the faulting frame with the modules' unwind tables,
/// writing each return address.
#[cfg(target_arch = "x86_64")]
unsafe fn unwind(mut context: windows::Win32::System::Diagnostics::Debug::CONTEXT) {
    use windows::Win32::System::Diagnostics::Debug::{
        RtlLookupFunctionEntry, RtlVirtualUnwind, UNW_FLAG_NHANDLER,
    };
    for n in 1..=FRAMES {
        let pc = context.Rip;
        let mut base = 0u64;
        let entry = RtlLookupFunctionEntry(pc, &mut base, None);
        if entry.is_null() {
            // A leaf function: its return address is on top of the stack.
            if context.Rsp == 0 {
                break;
            }
            context.Rip = *(context.Rsp as *const u64);
            context.Rsp += 8;
        } else {
            let mut handler_data = std::ptr::null_mut();
            let mut establisher = 0u64;
            RtlVirtualUnwind(
                UNW_FLAG_NHANDLER,
                base,
                pc,
                entry,
                &mut context,
                &mut handler_data,
                &mut establisher,
                None,
            );
        }
        if context.Rip == 0 {
            break;
        }
        let mut line = Line::start();
        let _ = write!(line, "  #{n} ");
        frame(&mut line, context.Rip as usize);
        line.end();
    }
}

/// `0x… in <module path>+0x…`, where the address is in a loaded module.
unsafe fn frame(line: &mut Line, address: usize) {
    let _ = write!(line, "{address:#x}");
    let mut module = HMODULE::default();
    if GetModuleHandleExW(
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        PCWSTR(address as *const u16),
        &mut module,
    )
    .is_err()
    {
        return;
    }
    let mut path = [0u16; 260];
    let len = GetModuleFileNameW(Some(module), &mut path) as usize;
    line.text(" in ");
    // UTF-16 to UTF-8 a character at a time: nothing allocated.
    for c in char::decode_utf16(path[..len.min(path.len())].iter().copied()) {
        let mut buffer = [0u8; 4];
        line.text(c.unwrap_or('?').encode_utf8(&mut buffer));
    }
    let _ = write!(line, "+{:#x}", address.wrapping_sub(module.0 as usize));
}
