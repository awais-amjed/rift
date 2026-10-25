//! threadtop on Windows: each thread's CPU (GetThreadTimes), context
//! switches (the system process list), priority, its name, and the module
//! it started in. Priority 15 is TIME_CRITICAL; a thread in an MMCSS task
//! ("Pro Audio") reads as its boosted value.
use super::sample_windows as sample;
use std::ffi::c_void;
use std::mem::{size_of, zeroed};
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::System::Diagnostics::ToolHelp::*;
use windows_sys::Win32::System::ProcessStatus::*;
use windows_sys::Win32::System::Threading::*;

#[link(name = "ntdll")]
extern "system" {
    fn NtQueryInformationThread(
        h: HANDLE,
        class: u32,
        info: *mut c_void,
        len: u32,
        ret: *mut u32,
    ) -> i32;
    fn NtQuerySystemInformation(class: u32, info: *mut c_void, len: u32, ret: *mut u32) -> i32;
}
#[link(name = "kernel32")]
extern "system" {
    fn GetThreadDescription(h: HANDLE, name: *mut *mut u16) -> i32;
    fn LocalFree(p: *mut c_void) -> *mut c_void;
}

fn threads(pid: u32) -> Vec<u32> {
    let mut out = Vec::new();
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        let mut e: THREADENTRY32 = zeroed();
        e.dwSize = size_of::<THREADENTRY32>() as u32;
        if Thread32First(snap, &mut e) != 0 {
            loop {
                if e.th32OwnerProcessID == pid {
                    out.push(e.th32ThreadID);
                }
                if Thread32Next(snap, &mut e) == 0 {
                    break;
                }
            }
        }
        CloseHandle(snap);
    }
    out
}

fn cpu_ms(h: HANDLE) -> f64 {
    unsafe {
        let (mut a, mut b, mut k, mut u): (FILETIME, FILETIME, FILETIME, FILETIME) =
            (zeroed(), zeroed(), zeroed(), zeroed());
        GetThreadTimes(h, &mut a, &mut b, &mut k, &mut u);
        let t = |f: FILETIME| {
            ((f.dwHighDateTime as u64) << 32 | f.dwLowDateTime as u64) as f64 / 10_000.0
        };
        t(k) + t(u)
    }
}

/// Context switches per thread id, from the system process list.
fn switches(pid: u32) -> std::collections::HashMap<u32, u32> {
    let mut map = std::collections::HashMap::new();
    let mut buf = vec![0u8; 8 << 20];
    let mut ret = 0;
    unsafe {
        if NtQuerySystemInformation(5, buf.as_mut_ptr() as _, buf.len() as u32, &mut ret) != 0 {
            return map;
        }
        let mut off = 0usize;
        loop {
            let p = buf.as_ptr().add(off);
            let next = *(p as *const u32) as usize;
            let nthreads = *(p.add(4) as *const u32) as usize;
            let upid = *(p.add(0x50) as *const usize) as u32;
            if upid == pid {
                // SYSTEM_PROCESS_INFORMATION is 0x100 bytes on x64; each thread entry 0x50.
                for i in 0..nthreads {
                    let t = p.add(0x100 + i * 0x50);
                    let tid = *(t.add(0x30) as *const usize) as u32; // ClientId.UniqueThread
                    let cs = *(t.add(0x40) as *const u32);
                    map.insert(tid, cs);
                }
            }
            if next == 0 {
                break;
            }
            off += next;
        }
    }
    map
}

pub fn find(name: &str) -> Option<u32> {
    let want = name.to_lowercase();
    let want = want.strip_suffix(".exe").unwrap_or(&want);
    let mut best: Option<(u32, u32)> = None;
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        let mut e: PROCESSENTRY32W = zeroed();
        e.dwSize = size_of::<PROCESSENTRY32W>() as u32;
        if Process32FirstW(snap, &mut e) != 0 {
            loop {
                let n = e
                    .szExeFile
                    .iter()
                    .position(|&c| c == 0)
                    .unwrap_or(e.szExeFile.len());
                let exe = String::from_utf16_lossy(&e.szExeFile[..n]).to_lowercase();
                if exe.strip_suffix(".exe").unwrap_or(&exe) == want
                    && best.map_or(true, |(_, t)| e.cntThreads > t)
                {
                    best = Some((e.th32ProcessID, e.cntThreads));
                }
                if Process32NextW(snap, &mut e) == 0 {
                    break;
                }
            }
        }
        CloseHandle(snap);
    }
    best.map(|(pid, _)| pid)
}

pub fn run(pid: u32, secs: f64, sampling: bool) {
    // Modules, to place each thread's start address.
    let mut mods: Vec<(usize, usize, String)> = Vec::new();
    unsafe {
        let ph = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, 0, pid);
        let mut hm = vec![0 as HMODULE; 1024];
        let mut need = 0;
        EnumProcessModules(ph, hm.as_mut_ptr(), (hm.len() * 8) as u32, &mut need);
        for &m in &hm[..(need as usize / 8)] {
            let mut mi: MODULEINFO = zeroed();
            GetModuleInformation(ph, m, &mut mi, size_of::<MODULEINFO>() as u32);
            let mut name = [0u16; 260];
            let n = GetModuleBaseNameW(ph, m, name.as_mut_ptr(), 260);
            mods.push((
                mi.lpBaseOfDll as usize,
                mi.SizeOfImage as usize,
                String::from_utf16_lossy(&name[..n as usize]),
            ));
        }
    }
    let tids = threads(pid);
    if sampling {
        sample::run(pid, secs, &mods, &tids);
        return;
    }
    let mut rows = Vec::new();
    let cs0 = switches(pid);
    for &tid in &tids {
        unsafe {
            let h = OpenThread(THREAD_QUERY_INFORMATION, 0, tid);
            if h.is_null() {
                continue;
            }
            let mut start: usize = 0;
            NtQueryInformationThread(h, 9, &mut start as *mut usize as _, 8, std::ptr::null_mut());
            let mut pname: *mut u16 = std::ptr::null_mut();
            let mut name = String::new();
            if GetThreadDescription(h, &mut pname) >= 0 && !pname.is_null() {
                let mut n = 0;
                while *pname.add(n) != 0 {
                    n += 1;
                }
                name = String::from_utf16_lossy(std::slice::from_raw_parts(pname, n));
                LocalFree(pname as _);
            }
            let module = mods
                .iter()
                .find(|(b, s, _)| start >= *b && start < b + s)
                .map(|(b, _, n)| format!("{n}+{:#x}", start - b))
                .unwrap_or(format!("{start:#x}"));
            rows.push((tid, h, cpu_ms(h), name, module));
        }
    }
    std::thread::sleep(std::time::Duration::from_secs_f64(secs));
    let cs1 = switches(pid);
    let mut out: Vec<_> = rows
        .into_iter()
        .map(|(tid, h, c0, name, module)| unsafe {
            let pct = (cpu_ms(h) - c0) / (secs * 10.0);
            let prio = GetThreadPriority(h);
            CloseHandle(h);
            let cs = cs1
                .get(&tid)
                .copied()
                .unwrap_or(0)
                .saturating_sub(cs0.get(&tid).copied().unwrap_or(0)) as f64
                / secs;
            (pct, cs, tid, prio, name, module)
        })
        .collect();
    out.sort_by(|a, b| (b.0 + b.1 / 1e4).partial_cmp(&(a.0 + a.1 / 1e4)).unwrap());
    let total: f64 = out.iter().map(|r| r.0).sum();
    let wakes: f64 = out.iter().map(|r| r.1).sum();
    println!(
        "total {total:.1}% of a core, {wakes:.0} switches/s, {} threads",
        out.len()
    );
    println!(
        "{:>6} {:>8} {:>6} {:>4}  {:<28} {}",
        "cpu%", "sw/s", "tid", "prio", "name", "start"
    );
    for (pct, cs, tid, prio, name, module) in out.iter().filter(|r| r.0 >= 0.2 || r.1 >= 20.0) {
        println!("{pct:>6.1} {cs:>8.0} {tid:>6} {prio:>4}  {name:<28} {module}");
    }
}
