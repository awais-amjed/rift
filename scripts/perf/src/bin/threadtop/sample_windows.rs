//! threadtop sample PID SECONDS: pauses every thread that ran since the last
//! look, about every 2 ms, and counts where it was: the module of the
//! instruction, and the first app module found on its stack.
use std::collections::HashMap;
use std::ffi::c_void;
use std::mem::zeroed;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::System::Diagnostics::Debug::*;
use windows_sys::Win32::System::Threading::*;

#[link(name = "kernel32")]
extern "system" {
    fn QueryThreadCycleTime(h: HANDLE, cycles: *mut u64) -> i32;
}

const SYSTEM: &[&str] = &[
    "ntdll.dll",
    "kernel32.dll",
    "kernelbase.dll",
    "ucrtbase.dll",
    "msvcp_win.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "msvcp140.dll",
    "combase.dll",
    "rpcrt4.dll",
    "win32u.dll",
    "user32.dll",
    "gdi32.dll",
    "gdi32full.dll",
    "sechost.dll",
];

pub fn run(pid: u32, secs: f64, mods: &[(usize, usize, String)], tids: &[u32]) {
    let module = |a: usize| mods.iter().find(|(b, s, _)| a >= *b && a < b + s);
    let place = |a: usize| module(a).map(|(b, _, n)| format!("{n}+{:#x}", a - b));
    unsafe {
        let ph = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, 0, pid);
        let mut hs: Vec<(u32, HANDLE, u64)> = tids
            .iter()
            .filter_map(|&t| {
                let h = OpenThread(
                    THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION,
                    0,
                    t,
                );
                if h.is_null() {
                    None
                } else {
                    let mut c = 0;
                    QueryThreadCycleTime(h, &mut c);
                    Some((t, h, c))
                }
            })
            .collect();
        let mut by_rip: HashMap<String, u32> = HashMap::new();
        let mut by_caller: HashMap<(u32, String), u32> = HashMap::new();
        let mut by_chain: HashMap<String, u32> = HashMap::new();
        let mut total = 0u32;
        let end = std::time::Instant::now() + std::time::Duration::from_secs_f64(secs);
        let mut stack = vec![0usize; 8192];
        while std::time::Instant::now() < end {
            for (tid, h, last) in hs.iter_mut() {
                let mut c = 0;
                QueryThreadCycleTime(*h, &mut c);
                let ran = c - *last;
                *last = c;
                // Pausing a thread costs it some cycles itself; a thread that
                // really ran in the last 2 ms has far more.
                if ran < 400_000 {
                    continue;
                }
                if SuspendThread(*h) == u32::MAX {
                    continue;
                }
                let mut ctx: CONTEXT = zeroed();
                ctx.ContextFlags = CONTEXT_CONTROL_AMD64 | CONTEXT_INTEGER_AMD64;
                let ok = GetThreadContext(*h, &mut ctx) != 0;
                let mut read = 0usize;
                if ok {
                    ReadProcessMemory(
                        ph,
                        ctx.Rsp as *const c_void,
                        stack.as_mut_ptr() as _,
                        stack.len() * 8,
                        &mut read,
                    );
                    if read == 0 {
                        // Ran off the stack's end: read less.
                        ReadProcessMemory(
                            ph,
                            ctx.Rsp as *const c_void,
                            stack.as_mut_ptr() as _,
                            4096,
                            &mut read,
                        );
                    }
                }
                ResumeThread(*h);
                let mut c2 = 0;
                QueryThreadCycleTime(*h, &mut c2);
                *last = c2;
                if !ok {
                    continue;
                }
                total += 1;
                let rip = ctx.Rip as usize;
                let rip_mod = module(rip).map(|m| m.2.clone()).unwrap_or("?".into());
                *by_rip.entry(rip_mod.clone()).or_default() += 1;
                let words = &stack[..read / 8];
                let mut app: Vec<String> = Vec::new();
                if !SYSTEM.contains(&rip_mod.to_lowercase().as_str()) && rip_mod != "?" {
                    app.push(place(rip).unwrap());
                }
                for &w in words {
                    if app.len() >= 3 {
                        break;
                    }
                    if let Some((_, _, n)) = module(w) {
                        if !SYSTEM.contains(&n.to_lowercase().as_str()) {
                            app.push(place(w).unwrap());
                        }
                    }
                }
                let first = app.first().cloned().unwrap_or("(system only)".into());
                *by_caller.entry((*tid, first)).or_default() += 1;
                *by_chain.entry(app.join(" < ")).or_default() += 1;
            }
            std::thread::sleep(std::time::Duration::from_millis(2));
        }
        println!("{total} samples");
        let show = |title: &str, v: Vec<(String, u32)>, n: usize| {
            println!("-- {title}");
            let mut v = v;
            v.sort_by(|a, b| b.1.cmp(&a.1));
            for (k, c) in v.into_iter().take(n) {
                println!("{:>6} {:>5.1}%  {k}", c, c as f64 * 100.0 / total as f64);
            }
        };
        show("module the thread was in", by_rip.into_iter().collect(), 12);
        show(
            "thread, first app address on its stack",
            by_caller
                .into_iter()
                .map(|((t, k), c)| (format!("{t:>6} {k}"), c))
                .collect(),
            25,
        );
        show("app chains", by_chain.into_iter().collect(), 25);
        for (_, h, _) in hs {
            CloseHandle(h);
        }
    }
}
