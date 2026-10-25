//! A stand-in for a CPU-bound game: threads doing the same fixed work per
//! "frame", timing every frame. A frame that takes longer than the fastest
//! one was held up by something else on the computer, so the share of slow
//! frames is how much another program (Rift) costs a game that wants every
//! core.
//!
//!   gameloop calibrate                          spin count for a ~5 ms frame
//!   gameloop run SECONDS SPINS LABEL [THREADS]  frame-time summary
//!
//! THREADS defaults to one per logical CPU. Each run's line is also appended
//! to results.txt in the current folder.
use std::hint::black_box;
use std::io::Write;
use std::sync::{Arc, Barrier};
use std::time::{Duration, Instant};

const USAGE: &str = "usage:\n  gameloop calibrate\n  gameloop run SECONDS SPINS LABEL [THREADS]";

fn work(spins: u64) -> u64 {
    let mut x: u64 = 0x9E3779B97F4A7C15;
    for _ in 0..spins {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        x = black_box(x);
    }
    x
}

fn pct(sorted: &[f64], p: f64) -> f64 {
    sorted[((sorted.len() as f64 - 1.0) * p).round() as usize]
}

fn calibrate() {
    let mut best = f64::MAX;
    let spins = 10_000_000u64;
    for _ in 0..20 {
        let t = Instant::now();
        black_box(work(spins));
        best = best.min(t.elapsed().as_secs_f64());
    }
    println!("{}", (spins as f64 * 0.005 / best) as u64);
}

fn run(secs: u64, spins: u64, label: &str, threads: usize) {
    let barrier = Arc::new(Barrier::new(threads));
    let end = Duration::from_secs(secs);
    let handles: Vec<_> = (0..threads)
        .map(|_| {
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                barrier.wait();
                let start = Instant::now();
                let mut times = Vec::new();
                while start.elapsed() < end {
                    let t = Instant::now();
                    black_box(work(spins));
                    times.push(t.elapsed().as_secs_f64() * 1000.0);
                }
                times
            })
        })
        .collect();
    let per: Vec<Vec<f64>> = handles.into_iter().map(|h| h.join().unwrap()).collect();
    let mut all: Vec<f64> = per.concat();
    all.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let fastest = all[0];
    let over =
        |f: f64| all.iter().filter(|&&t| t > fastest * f).count() as f64 / all.len() as f64 * 100.0;
    let line = format!(
        "{label}: threads {threads} frames {} | median {:.3} p99 {:.3} p99.9 {:.3} max {:.2} ms | >1.2x {:.2}% >1.5x {:.3}% >2x {:.3}% | fastest {:.3}",
        all.len(),
        pct(&all, 0.5),
        pct(&all, 0.99),
        pct(&all, 0.999),
        all[all.len() - 1],
        over(1.2),
        over(1.5),
        over(2.0),
        fastest
    );
    println!("{line}");
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("results.txt")
        .unwrap();
    writeln!(f, "{line}").unwrap();
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("calibrate") => calibrate(),
        Some("run") if args.len() >= 5 => {
            let threads = match args.get(5) {
                Some(n) => n.parse().expect("THREADS"),
                None => std::thread::available_parallelism().unwrap().get(),
            };
            run(
                args[2].parse().expect("SECONDS"),
                args[3].parse().expect("SPINS"),
                &args[4],
                threads,
            );
        }
        _ => {
            eprintln!("{USAGE}");
            std::process::exit(2);
        }
    }
}
