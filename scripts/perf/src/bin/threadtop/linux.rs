//! threadtop on Linux, from /proc: CPU from each task's utime + stime,
//! switches from its status file, and the scheduling policy, which is where
//! a real-time audio thread would show (FIFO or RR) — Linux's libwebrtc
//! capture thread runs as an ordinary one.
use std::collections::HashMap;
use std::fs;

struct Task {
    name: String,
    ticks: u64,
    switches: u64,
    nice: i64,
    policy: u32,
}

pub fn find(name: &str) -> Option<u32> {
    let want = name.to_lowercase();
    let mut best: Option<(u32, usize)> = None;
    for entry in fs::read_dir("/proc").ok()?.flatten() {
        let Ok(pid) = entry.file_name().to_string_lossy().parse::<u32>() else {
            continue;
        };
        let Ok(comm) = fs::read_to_string(format!("/proc/{pid}/comm")) else {
            continue;
        };
        if comm.trim().to_lowercase() != want {
            continue;
        }
        // The busiest match: a launcher shell shares the name with fewer threads.
        let threads = fs::read_dir(format!("/proc/{pid}/task"))
            .map(|d| d.count())
            .unwrap_or(0);
        if best.map_or(true, |(_, n)| threads > n) {
            best = Some((pid, threads));
        }
    }
    best.map(|(pid, _)| pid)
}

fn tasks(pid: u32) -> HashMap<u32, Task> {
    let mut out = HashMap::new();
    let Ok(dir) = fs::read_dir(format!("/proc/{pid}/task")) else {
        return out;
    };
    for entry in dir.flatten() {
        let Ok(tid) = entry.file_name().to_string_lossy().parse::<u32>() else {
            continue;
        };
        let base = format!("/proc/{pid}/task/{tid}");
        let Ok(stat) = fs::read_to_string(format!("{base}/stat")) else {
            continue;
        };
        // The name sits in parentheses and may hold spaces; fields follow the last ')'.
        let (Some(open), Some(close)) = (stat.find('('), stat.rfind(')')) else {
            continue;
        };
        let name = stat[open + 1..close].to_string();
        let f: Vec<&str> = stat[close + 2..].split_whitespace().collect();
        let num = |i: usize| f.get(i).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
        let mut switches = 0;
        if let Ok(status) = fs::read_to_string(format!("{base}/status")) {
            for line in status.lines() {
                if line.starts_with("voluntary_ctxt_switches")
                    || line.starts_with("nonvoluntary_ctxt_switches")
                {
                    switches += line
                        .split_whitespace()
                        .nth(1)
                        .and_then(|n| n.parse::<u64>().ok())
                        .unwrap_or(0);
                }
            }
        }
        out.insert(
            tid,
            Task {
                name,
                // stat fields 14 and 15, counted from 3 after the name.
                ticks: (num(11) + num(12)) as u64,
                switches,
                nice: num(16),
                policy: num(38) as u32,
            },
        );
    }
    out
}

fn clock_ticks() -> f64 {
    std::process::Command::new("getconf")
        .arg("CLK_TCK")
        .output()
        .ok()
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(100.0)
}

fn policy(p: u32) -> &'static str {
    match p {
        0 => "other",
        1 => "FIFO",
        2 => "RR",
        3 => "batch",
        5 => "idle",
        6 => "deadline",
        _ => "?",
    }
}

pub fn run(pid: u32, secs: f64) {
    let hz = clock_ticks();
    let before = tasks(pid);
    std::thread::sleep(std::time::Duration::from_secs_f64(secs));
    let after = tasks(pid);
    let mut rows: Vec<(f64, f64, u32, &Task)> = after
        .iter()
        .filter_map(|(tid, t)| {
            let b = before.get(tid)?;
            let pct = (t.ticks.saturating_sub(b.ticks)) as f64 / hz / secs * 100.0;
            let sw = t.switches.saturating_sub(b.switches) as f64 / secs;
            Some((pct, sw, *tid, t))
        })
        .collect();
    rows.sort_by(|a, b| (b.0 + b.1 / 1e4).partial_cmp(&(a.0 + a.1 / 1e4)).unwrap());
    let total: f64 = rows.iter().map(|r| r.0).sum();
    let wakes: f64 = rows.iter().map(|r| r.1).sum();
    println!(
        "total {total:.1}% of a core, {wakes:.0} switches/s, {} threads",
        rows.len()
    );
    println!(
        "{:>6} {:>8} {:>7} {:>4} {:>8}  {}",
        "cpu%", "sw/s", "tid", "nice", "policy", "name"
    );
    for (pct, sw, tid, t) in rows.iter().filter(|r| r.0 >= 0.2 || r.1 >= 20.0) {
        println!(
            "{pct:>6.1} {sw:>8.0} {tid:>7} {:>4} {:>8}  {}",
            t.nice,
            policy(t.policy),
            t.name
        );
    }
}
