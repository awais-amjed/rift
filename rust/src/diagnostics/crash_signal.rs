//! Linux and Android: a crash in native code, written into the log as it
//! happens.
//!
//! Linux keeps no record of a crash that every distribution has (systemd's
//! coredumps, Ubuntu's apport, or nothing), so Rift catches the signal itself.
//! The handler writes the signal, the address it faulted on, and the stack as
//! far as it unwinds, each frame as a library and an offset, then passes the
//! signal on to whoever had it before: the default action, which ends the
//! process as it would have, or on Android debuggerd, which still writes its
//! tombstone. ART goes first on Android whatever is installed after it (its
//! sigchain), so the null checks it makes by faulting never get here.
//!
//! Inside a signal handler nearly nothing is safe. So the lines are made in a
//! buffer on the stack, written with one `write` each to the log file's
//! descriptor ([crate::logging::file_raw]) without its lock, and nothing is
//! allocated. `dladdr` and the unwinder can take a lock the crashing thread
//! held, so an alarm ends the process if the handler hangs.
use std::cell::UnsafeCell;
use std::ffi::{c_int, c_void, CStr};
use std::fmt::Write;
use std::sync::atomic::{AtomicBool, Ordering};

use super::crash_line::Line;

const SIGNALS: [c_int; 6] = [
    libc::SIGSEGV,
    libc::SIGBUS,
    libc::SIGILL,
    libc::SIGFPE,
    libc::SIGABRT,
    libc::SIGTRAP,
];

/// Frames written after the faulting one.
const FRAMES: usize = 32;

/// Seconds the handler has before the process is ended anyway.
const HANDLER_SECONDS: u32 = 5;

/// What each of [SIGNALS] did before, written once at install and only read
/// after.
struct Previous(UnsafeCell<[libc::sigaction; SIGNALS.len()]>);

// SAFETY: written only by `install`, under `INSTALLED`, before the handler
// that reads it is in place.
unsafe impl Sync for Previous {}

static PREVIOUS: Previous = Previous(UnsafeCell::new(unsafe { std::mem::zeroed() }));
static INSTALLED: AtomicBool = AtomicBool::new(false);
/// Set by the first crash written, so two threads crashing together do not
/// interleave their lines; the second only passes its signal on.
static HANDLING: AtomicBool = AtomicBool::new(false);

/// Puts the handler in front of each of [SIGNALS]. Once per process.
pub(crate) fn install() {
    if INSTALLED.swap(true, Ordering::AcqRel) {
        return;
    }
    // SAFETY: `PREVIOUS` is written here only, before any handler reads it.
    unsafe {
        let previous = &mut *PREVIOUS.0.get();
        for (i, &signal) in SIGNALS.iter().enumerate() {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = on_crash as *const () as usize;
            // Not SA_ONSTACK: a thread's alternate stack, where one has it,
            // is a few kilobytes, and formatting a line there overflowed it
            // (the Rust test harness's threads). On the thread's own stack,
            // only a stack overflow goes unwritten, which then ends the
            // process as it did before.
            action.sa_flags = libc::SA_SIGINFO;
            libc::sigemptyset(&mut action.sa_mask);
            if libc::sigaction(signal, &action, &mut previous[i]) != 0 {
                log::info!("crash: no handler for signal {signal}");
            }
        }
    }
}

extern "C" fn on_crash(signal: c_int, info: *mut libc::siginfo_t, context: *mut c_void) {
    if !HANDLING.swap(true, Ordering::AcqRel) {
        // SAFETY: async-signal-safe calls, and `write_crash` keeps to them
        // but for dladdr and the unwinder, which the alarm covers.
        unsafe {
            libc::alarm(HANDLER_SECONDS);
            write_crash(signal, info, context);
            // debuggerd can take longer than that over its tombstone.
            libc::alarm(0);
        }
    }
    // SAFETY: hands the signal to what had it, with what the kernel gave us.
    unsafe { pass_on(signal, info, context) };
}

/// # Safety
/// From the handler only, with its arguments.
unsafe fn pass_on(signal: c_int, info: *mut libc::siginfo_t, context: *mut c_void) {
    let Some(i) = SIGNALS.iter().position(|&s| s == signal) else {
        return;
    };
    let previous = &(*PREVIOUS.0.get())[i];
    let handler = previous.sa_sigaction;
    if handler == libc::SIG_DFL || handler == libc::SIG_IGN {
        // The default action back in place: a fault happens again as the
        // handler returns, and a signal someone sent is sent again.
        let mut default: libc::sigaction = std::mem::zeroed();
        default.sa_sigaction = libc::SIG_DFL;
        libc::sigaction(signal, &default, std::ptr::null_mut());
        if info.is_null() || (*info).si_code <= 0 {
            libc::raise(signal);
        }
        return;
    }
    if previous.sa_flags & libc::SA_SIGINFO != 0 {
        let handler: extern "C" fn(c_int, *mut libc::siginfo_t, *mut c_void) =
            std::mem::transmute(handler);
        handler(signal, info, context);
    } else {
        let handler: extern "C" fn(c_int) = std::mem::transmute(handler);
        handler(signal);
    }
}

/// # Safety
/// From the handler only, with its arguments.
unsafe fn write_crash(signal: c_int, info: *mut libc::siginfo_t, context: *mut c_void) {
    let mut line = Line::start();
    let _ = write!(line, "{} (code ", signal_name(signal));
    if info.is_null() {
        line.text("unknown");
    } else if (*info).si_code <= 0 {
        // Sent by a process (kill, abort), not a fault: no address to give.
        let _ = write!(line, "{}, sent", (*info).si_code);
    } else {
        let _ = write!(
            line,
            "{}, address {:#x}",
            (*info).si_code,
            (*info).si_addr() as usize
        );
    }
    let _ = write!(line, ") on thread {}", libc::syscall(libc::SYS_gettid));
    let mut name = [0u8; 16];
    if libc::prctl(libc::PR_GET_NAME, name.as_mut_ptr()) == 0 {
        line.text(" \"");
        line.bytes(until_nul(&name));
        line.text("\"");
    }
    line.end();

    let pc = program_counter(context);
    if pc != 0 {
        let mut line = Line::start();
        line.text("  at ");
        frame(&mut line, pc);
        line.end();
    }

    let mut walk = Walk {
        pc,
        found: pc == 0,
        written: 0,
        frames: [0; FRAMES],
    };
    _Unwind_Backtrace(each_frame, (&mut walk as *mut Walk).cast());
    // Unwound without passing the fault: the stack as it is, handler and all.
    if !walk.found {
        walk.written = 0;
        walk.found = true;
        _Unwind_Backtrace(each_frame, (&mut walk as *mut Walk).cast());
    }
    for (n, &ip) in walk.frames[..walk.written].iter().enumerate() {
        let mut line = Line::start();
        let _ = write!(line, "  #{} ", n + 1);
        frame(&mut line, ip);
        line.end();
    }
}

/// `0x… in <library>+0x… (<symbol>+0x…)`, as far as `dladdr` knows.
unsafe fn frame(line: &mut Line, ip: usize) {
    let _ = write!(line, "{ip:#x}");
    let mut info: libc::Dl_info = std::mem::zeroed();
    if libc::dladdr(ip as *const c_void, &mut info) == 0 {
        return;
    }
    if !info.dli_fname.is_null() {
        line.text(" in ");
        line.bytes(CStr::from_ptr(info.dli_fname).to_bytes());
        let _ = write!(line, "+{:#x}", ip.wrapping_sub(info.dli_fbase as usize));
    }
    if !info.dli_sname.is_null() {
        line.text(" (");
        line.bytes(CStr::from_ptr(info.dli_sname).to_bytes());
        let _ = write!(line, "+{:#x})", ip.wrapping_sub(info.dli_saddr as usize));
    }
}

struct Walk {
    /// The faulting instruction, and whether the unwind has reached it: the
    /// frames before are the handler's own and the kernel's trampoline.
    pc: usize,
    found: bool,
    written: usize,
    frames: [usize; FRAMES],
}

extern "C" fn each_frame(context: *mut c_void, data: *mut c_void) -> c_int {
    // SAFETY: `data` is the `Walk` handed to `_Unwind_Backtrace`.
    let walk = unsafe { &mut *data.cast::<Walk>() };
    let ip = unsafe { _Unwind_GetIP(context) };
    if !walk.found {
        // The faulting frame is a signal frame, whose address is the
        // instruction itself rather than one past a call.
        walk.found = ip == walk.pc || ip == walk.pc + 1;
        return URC_NO_REASON;
    }
    if walk.written == FRAMES || ip == 0 {
        return URC_END_OF_STACK;
    }
    walk.frames[walk.written] = ip;
    walk.written += 1;
    URC_NO_REASON
}

const URC_NO_REASON: c_int = 0;
const URC_END_OF_STACK: c_int = 5;

extern "C" {
    // The unwinder std already links: libgcc_s on Linux, LLVM's libunwind on
    // Android.
    fn _Unwind_Backtrace(
        trace: extern "C" fn(*mut c_void, *mut c_void) -> c_int,
        data: *mut c_void,
    ) -> c_int;
    fn _Unwind_GetIP(context: *mut c_void) -> usize;
}

/// The faulting instruction, from the context the kernel saved.
unsafe fn program_counter(context: *mut c_void) -> usize {
    if context.is_null() {
        return 0;
    }
    let context = &*context.cast::<libc::ucontext_t>();
    #[cfg(target_arch = "x86_64")]
    return context.uc_mcontext.gregs[libc::REG_RIP as usize] as usize;
    #[cfg(target_arch = "x86")]
    return context.uc_mcontext.gregs[libc::REG_EIP as usize] as usize;
    #[cfg(target_arch = "aarch64")]
    return context.uc_mcontext.pc as usize;
    #[cfg(target_arch = "arm")]
    return context.uc_mcontext.arm_pc as usize;
    #[cfg(not(any(
        target_arch = "x86_64",
        target_arch = "x86",
        target_arch = "aarch64",
        target_arch = "arm"
    )))]
    {
        let _ = context;
        0
    }
}

fn signal_name(signal: c_int) -> &'static str {
    match signal {
        libc::SIGSEGV => "SIGSEGV",
        libc::SIGBUS => "SIGBUS",
        libc::SIGILL => "SIGILL",
        libc::SIGFPE => "SIGFPE",
        libc::SIGABRT => "SIGABRT",
        libc::SIGTRAP => "SIGTRAP",
        _ => "signal",
    }
}

fn until_nul(bytes: &[u8]) -> &[u8] {
    &bytes[..bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len())]
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Run again as a child, which installs the handler, opens a log and
    /// writes through a bad pointer; the parent reads what reached the file.
    #[test]
    fn a_crash_is_written_to_the_log_and_still_ends_the_process() {
        const CHILD: &str = "RIFT_CRASH_TEST_DIR";
        if let Ok(dir) = std::env::var(CHILD) {
            crate::logging::start(std::path::Path::new(&dir)).unwrap();
            install();
            crashes_here();
            unreachable!();
        }
        let dir = std::env::temp_dir().join(format!("rift-crash-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "diagnostics::crash_signal::tests::a_crash_is_written_to_the_log_and_still_ends_the_process",
                "--exact",
                "--test-threads=1",
                "--nocapture",
            ])
            .env(CHILD, &dir)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .unwrap();
        use std::os::unix::process::ExitStatusExt;
        assert_eq!(status.signal(), Some(libc::SIGSEGV), "{status:?}");

        let log = std::fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .map(|entry| std::fs::read_to_string(entry.path()).unwrap())
            .collect::<String>();
        let _ = std::fs::remove_dir_all(&dir);
        let crash: Vec<&str> = log
            .lines()
            .filter(|l| l.contains("CRASH native:"))
            .collect();
        assert!(
            crash[0].contains("SIGSEGV (code 1, address 0x8) on thread"),
            "{log}"
        );
        assert!(crash[1].contains("  at 0x"), "{log}");
        assert!(crash.len() > 2, "the stack below it: {log}");
    }

    #[inline(never)]
    fn crashes_here() {
        // SAFETY: not safe at all; that is the test.
        unsafe { std::ptr::write_volatile(8 as *mut u8, 1) };
    }
}
