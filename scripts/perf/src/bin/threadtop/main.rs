//! Where a process's CPU goes, thread by thread.
//!
//!   threadtop PID|NAME SECONDS          each thread's CPU over SECONDS (% of
//!                                       one core), switches/s, priority, name
//!   threadtop sample PID|NAME SECONDS   (Windows) where the busy threads are
//!                                       in the code, by module
//!
//! NAME is matched case-insensitively against the executable's name without
//! `.exe`: `riftchat` finds RiftChat.exe on Windows and riftchat on Linux.
#[cfg(target_os = "linux")]
mod linux;
#[cfg(windows)]
mod sample_windows;
#[cfg(windows)]
mod windows;

const USAGE: &str =
    "usage:\n  threadtop PID|NAME SECONDS\n  threadtop sample PID|NAME SECONDS   (Windows only)";

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let sampling = args.get(1).map(String::as_str) == Some("sample");
    let rest = if sampling {
        &args[2.min(args.len())..]
    } else {
        &args[1.min(args.len())..]
    };
    if rest.len() < 2 {
        eprintln!("{USAGE}");
        std::process::exit(2);
    }
    let secs: f64 = rest[1].parse().expect("SECONDS");
    let pid = match rest[0].parse::<u32>() {
        Ok(pid) => pid,
        Err(_) => match find(&rest[0]) {
            Some(pid) => pid,
            None => {
                eprintln!("no process named {}", rest[0]);
                std::process::exit(1);
            }
        },
    };
    run(pid, secs, sampling);
}

#[cfg(windows)]
fn find(name: &str) -> Option<u32> {
    windows::find(name)
}

#[cfg(windows)]
fn run(pid: u32, secs: f64, sampling: bool) {
    windows::run(pid, secs, sampling);
}

#[cfg(target_os = "linux")]
fn find(name: &str) -> Option<u32> {
    linux::find(name)
}

#[cfg(target_os = "linux")]
fn run(pid: u32, secs: f64, sampling: bool) {
    if sampling {
        eprintln!("sample is Windows only: on Linux use `perf top -p {pid}` if perf is installed");
        std::process::exit(2);
    }
    linux::run(pid, secs);
}
