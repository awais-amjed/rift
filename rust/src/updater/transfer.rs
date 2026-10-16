//! An update's download, which the person can pause, resume and cancel, and
//! which says how fast it is going.
//!
//! Velopack's own download reads each package in one request to the end, and
//! nothing stops it but a failure. This one reads in small pieces and looks
//! between them at what the person asked: a pause lets the connection go and
//! the resume asks for the rest with a `Range` request (a server that answers
//! with the whole file again is read from the start), and a cancel ends the
//! read with an error, which ends Velopack's download — and, because the flag
//! stays up, the full package it falls back to when a delta fails.

use std::collections::VecDeque;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

use velopack::{Error, VelopackAsset};

/// The error a cancelled download ends with.
pub(crate) const CANCELLED: &str = "The download was cancelled";

/// How long a connection or a server's first answer may take.
const ANSWER_WAIT: Duration = Duration::from_secs(30);

/// One read: small enough that a pause or cancel is felt at once.
const PIECE: usize = 64 * 1024;

/// What the speed is averaged over.
const RATE_WINDOW: Duration = Duration::from_secs(3);

pub(crate) struct Transfer {
    state: Mutex<State>,
    changed: Condvar,
}

#[derive(Default)]
struct State {
    paused: bool,
    cancelled: bool,
    /// The packages the counts below are about.
    planned: Vec<String>,
    total: u64,
    done: u64,
}

/// What stopped a read.
#[derive(Debug, PartialEq)]
enum Stop {
    Pause,
    Cancel,
}

impl Transfer {
    pub(crate) fn new() -> Self {
        Transfer { state: Mutex::new(State::default()), changed: Condvar::new() }
    }

    /// Starts a download of `packages` over: nothing down, not paused, not
    /// cancelled.
    pub(crate) fn plan(&self, packages: &[&VelopackAsset]) {
        *self.state.lock().unwrap() = State {
            planned: packages.iter().map(|p| p.FileName.clone()).collect(),
            total: packages.iter().map(|p| p.Size).sum(),
            ..State::default()
        };
        self.changed.notify_all();
    }

    pub(crate) fn pause(&self) {
        self.state.lock().unwrap().paused = true;
        self.changed.notify_all();
    }

    pub(crate) fn resume(&self) {
        self.state.lock().unwrap().paused = false;
        self.changed.notify_all();
    }

    pub(crate) fn cancel(&self) {
        self.state.lock().unwrap().cancelled = true;
        self.changed.notify_all();
    }

    /// Bytes down and bytes in all, and whether it is paused.
    pub(crate) fn progress(&self) -> (u64, u64, bool) {
        let state = self.state.lock().unwrap();
        (state.done, state.total, state.paused)
    }

    /// Counts `asset` in. A package outside the plan is the full package
    /// Velopack falls back to when a delta fails, and the counts start again
    /// for it alone.
    fn begin(&self, asset: &VelopackAsset) {
        let mut state = self.state.lock().unwrap();
        if !state.planned.contains(&asset.FileName) {
            state.planned = vec![asset.FileName.clone()];
            state.total = asset.Size;
            state.done = 0;
        }
    }

    fn add(&self, bytes: u64) {
        self.state.lock().unwrap().done += bytes;
    }

    fn take_back(&self, bytes: u64) {
        let mut state = self.state.lock().unwrap();
        state.done = state.done.saturating_sub(bytes);
    }

    fn stop(&self) -> Option<Stop> {
        let state = self.state.lock().unwrap();
        if state.cancelled {
            Some(Stop::Cancel)
        } else if state.paused {
            Some(Stop::Pause)
        } else {
            None
        }
    }

    /// Waits out a pause; an error once cancelled.
    fn wait_unpaused(&self) -> Result<(), Error> {
        let mut state = self.state.lock().unwrap();
        while state.paused && !state.cancelled {
            state = self.changed.wait(state).unwrap();
        }
        if state.cancelled {
            Err(Error::Other(CANCELLED.to_string()))
        } else {
            Ok(())
        }
    }

    /// Downloads `asset` from `url` into `path`. A cancelled download takes
    /// its part-file with it.
    pub(crate) fn fetch(&self, url: &str, asset: &VelopackAsset, path: &Path) -> Result<(), Error> {
        self.begin(asset);
        let result = self.fetch_into(url, asset.Size, path);
        if self.stop() == Some(Stop::Cancel) {
            let _ = std::fs::remove_file(path);
        }
        result
    }

    fn fetch_into(&self, url: &str, size: u64, path: &Path) -> Result<(), Error> {
        let config =
            ureq::Agent::config_builder().timeout_connect(Some(ANSWER_WAIT)).timeout_recv_response(Some(ANSWER_WAIT));
        // The tests' server is on this machine, where a proxy named in the
        // environment cannot reach it.
        #[cfg(test)]
        let config = if url.starts_with("http://127.0.0.1") { config.proxy(None) } else { config };
        let agent: ureq::Agent = config.build().into();
        let mut file = File::create(path)?;
        let mut have: u64 = 0;
        let mut buffer = vec![0; PIECE];
        loop {
            self.wait_unpaused()?;
            // Paused with the last byte already in.
            if have > 0 && have >= size {
                return Ok(());
            }
            let mut request = agent.get(url).header("User-Agent", "Rift");
            if have > 0 {
                request = request.header("Range", format!("bytes={have}-"));
            }
            let response = request.call()?;
            if have > 0 && response.status().as_u16() != 206 {
                file.set_len(0)?;
                file.seek(SeekFrom::Start(0))?;
                self.take_back(have);
                have = 0;
            }
            let mut body = response.into_body().into_reader();
            loop {
                match self.stop() {
                    Some(Stop::Cancel) => return Err(Error::Other(CANCELLED.to_string())),
                    // Lets the connection go; the outer loop waits.
                    Some(Stop::Pause) => break,
                    None => {}
                }
                let read = body.read(&mut buffer)?;
                if read == 0 {
                    return Ok(());
                }
                file.write_all(&buffer[..read])?;
                have += read as u64;
                self.add(read as u64);
            }
        }
    }
}

/// How fast the bytes are coming, over the last few seconds.
#[derive(Default)]
pub(crate) struct Rate {
    samples: VecDeque<(Instant, u64)>,
}

impl Rate {
    /// Takes in a count of bytes down at `at`, and gives bytes a second; 0
    /// while paused and until there is a second to measure. The count going
    /// down (a fall back to the full package) starts the measure again.
    pub(crate) fn sample(&mut self, at: Instant, done: u64, paused: bool) -> u64 {
        if paused || self.samples.back().is_some_and(|&(_, d)| done < d) {
            self.samples.clear();
        }
        if paused {
            return 0;
        }
        self.samples.push_back((at, done));
        while self.samples.len() > 2 && at.duration_since(self.samples[1].0) >= RATE_WINDOW {
            self.samples.pop_front();
        }
        let (since, from) = self.samples[0];
        let seconds = at.duration_since(since).as_secs_f64();
        if seconds < 1.0 {
            return 0;
        }
        ((done - from) as f64 / seconds) as u64
    }
}

#[cfg(test)]
mod tests {
    use std::io::{BufRead, BufReader};
    use std::net::TcpListener;
    use std::sync::Arc;

    use super::*;

    fn asset(name: &str, size: u64) -> VelopackAsset {
        VelopackAsset { FileName: name.into(), Size: size, ..Default::default() }
    }

    /// A server of `data` that honours `Range` when `ranges`, sending it in
    /// small pieces with a pause between, so a test can stop it midway.
    /// Returns its URL and the `Range` header of each request.
    fn serve(data: Vec<u8>, ranges: bool) -> (String, Arc<Mutex<Vec<Option<String>>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/pkg", listener.local_addr().unwrap());
        let asked = Arc::new(Mutex::new(Vec::new()));
        let log = asked.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { return };
                let mut range = None;
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                loop {
                    let mut line = String::new();
                    if reader.read_line(&mut line).unwrap_or(0) == 0 || line == "\r\n" {
                        break;
                    }
                    if let Some(v) = line.to_ascii_lowercase().strip_prefix("range: bytes=") {
                        range = Some(v.trim().trim_end_matches('-').to_string());
                    }
                }
                log.lock().unwrap().push(range.clone());
                let from = if ranges { range.and_then(|r| r.parse::<usize>().ok()).unwrap_or(0) } else { 0 };
                let status = if from > 0 { "206 Partial Content" } else { "200 OK" };
                let head =
                    format!("HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", data.len() - from);
                let _ = stream.write_all(head.as_bytes());
                for piece in data[from..].chunks(4096) {
                    if stream.write_all(piece).is_err() {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(2));
                }
            }
        });
        (url, asked)
    }

    /// A part-file path of this test's own, gone first.
    fn scratch(name: &str) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!("rift-transfer-{}-{name}", std::process::id()));
        let _ = std::fs::remove_file(&path);
        path
    }

    fn data(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i * 7 % 251) as u8).collect()
    }

    fn wait_for(what: impl Fn() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(60);
        while !what() {
            assert!(Instant::now() < deadline, "timed out");
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    #[test]
    fn a_paused_download_resumes_with_the_rest() {
        let bytes = data(400 * 1024);
        let (url, asked) = serve(bytes.clone(), true);
        let path = scratch("resume");
        let transfer = Arc::new(Transfer::new());
        let pkg = asset("pkg", bytes.len() as u64);
        transfer.plan(&[&pkg]);
        let worker = {
            let (transfer, path) = (transfer.clone(), path.clone());
            std::thread::spawn(move || transfer.fetch(&url, &pkg, &path))
        };
        wait_for(|| transfer.progress().0 > 64 * 1024);
        transfer.pause();
        // A read under way when the pause came still lands.
        std::thread::sleep(Duration::from_millis(50));
        let held = transfer.progress().0;
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(transfer.progress().0, held, "nothing comes in while paused");
        transfer.resume();
        worker.join().unwrap().unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
        assert_eq!(transfer.progress().0, bytes.len() as u64);
        let asked = asked.lock().unwrap();
        assert_eq!(asked.len(), 2);
        assert_eq!(asked[0], None);
        assert_eq!(asked[1].as_deref(), Some(held.to_string().as_str()));
        let _ = std::fs::remove_file(&path);
    }

    /// A real package through GitHub's redirect to its storage, paused part
    /// way: `RIFT_PROBE_URL` of `RIFT_PROBE_SIZE` bytes, written to
    /// `RIFT_PROBE_OUT` for comparing with the feed's SHA-256.
    #[test]
    #[ignore]
    fn a_real_download_resumes() {
        let url = std::env::var("RIFT_PROBE_URL").unwrap();
        let size: u64 = std::env::var("RIFT_PROBE_SIZE").unwrap().parse().unwrap();
        let path = std::path::PathBuf::from(std::env::var("RIFT_PROBE_OUT").unwrap());
        let transfer = Arc::new(Transfer::new());
        let pkg = asset("pkg", size);
        transfer.plan(&[&pkg]);
        let worker = {
            let (transfer, path) = (transfer.clone(), path.clone());
            std::thread::spawn(move || transfer.fetch(&url, &pkg, &path))
        };
        wait_for(|| transfer.progress().0 > size / 3);
        transfer.pause();
        std::thread::sleep(Duration::from_millis(200));
        let held = transfer.progress().0;
        std::thread::sleep(Duration::from_secs(2));
        transfer.resume();
        let mut lowest = held;
        while !worker.is_finished() {
            lowest = lowest.min(transfer.progress().0);
            std::thread::sleep(Duration::from_millis(5));
        }
        worker.join().unwrap().unwrap();
        assert_eq!(lowest, held, "the resume carried on rather than starting again");
        assert_eq!(std::fs::metadata(&path).unwrap().len(), size);
    }

    #[test]
    fn a_server_without_ranges_starts_over() {
        let bytes = data(300 * 1024);
        let (url, asked) = serve(bytes.clone(), false);
        let path = scratch("over");
        let transfer = Arc::new(Transfer::new());
        let pkg = asset("pkg", bytes.len() as u64);
        transfer.plan(&[&pkg]);
        let worker = {
            let (transfer, path) = (transfer.clone(), path.clone());
            std::thread::spawn(move || transfer.fetch(&url, &pkg, &path))
        };
        wait_for(|| transfer.progress().0 > 64 * 1024);
        transfer.pause();
        std::thread::sleep(Duration::from_millis(50));
        transfer.resume();
        worker.join().unwrap().unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
        assert_eq!(transfer.progress().0, bytes.len() as u64);
        assert_eq!(asked.lock().unwrap().len(), 2);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_cancel_ends_it_and_takes_the_part_file() {
        let bytes = data(400 * 1024);
        let (url, _) = serve(bytes.clone(), true);
        let path = scratch("cancel");
        let transfer = Arc::new(Transfer::new());
        let pkg = asset("pkg", bytes.len() as u64);
        transfer.plan(&[&pkg]);
        let worker = {
            let (transfer, path, pkg) = (transfer.clone(), path.clone(), pkg.clone());
            std::thread::spawn(move || transfer.fetch(&url, &pkg, &path))
        };
        wait_for(|| transfer.progress().0 > 64 * 1024);
        transfer.cancel();
        let error = worker.join().unwrap().unwrap_err();
        assert!(error.to_string().contains(CANCELLED));
        assert!(!path.exists());
        // The full package Velopack falls back to is refused too.
        assert!(transfer.fetch("http://127.0.0.1:9/never", &pkg, &path).is_err());
    }

    #[test]
    fn a_cancel_ends_a_pause() {
        let transfer = Arc::new(Transfer::new());
        transfer.pause();
        let waiter = {
            let transfer = transfer.clone();
            std::thread::spawn(move || transfer.wait_unpaused())
        };
        std::thread::sleep(Duration::from_millis(50));
        transfer.cancel();
        assert!(waiter.join().unwrap().is_err());
    }

    #[test]
    fn a_package_outside_the_plan_starts_the_counts_again() {
        let transfer = Transfer::new();
        let (d1, d2) = (asset("d1", 100), asset("d2", 50));
        transfer.plan(&[&d1, &d2]);
        transfer.begin(&d1);
        transfer.add(100);
        transfer.begin(&d2);
        transfer.add(20);
        assert_eq!(transfer.progress(), (120, 150, false));
        transfer.begin(&asset("full", 900));
        assert_eq!(transfer.progress(), (0, 900, false));
    }

    #[test]
    fn the_rate_is_bytes_a_second_over_the_window() {
        let mut rate = Rate::default();
        let start = Instant::now();
        let at = |ms: u64| start + Duration::from_millis(ms);
        assert_eq!(rate.sample(at(0), 0, false), 0);
        assert_eq!(rate.sample(at(500), 500, false), 0, "under a second is no measure");
        assert_eq!(rate.sample(at(1000), 1000, false), 1000);
        for s in 2..=10 {
            rate.sample(at(s * 1000), s * 1000, false);
        }
        // Speeding up shows within the window, not averaged over the whole.
        for s in 11..=14 {
            rate.sample(at(s * 1000), 10_000 + (s - 10) * 5000, false);
        }
        assert_eq!(rate.sample(at(15_000), 35_000, false), 5000);
        assert_eq!(rate.sample(at(15_500), 35_000, true), 0);
        assert_eq!(rate.sample(at(16_000), 35_000, false), 0, "a resume measures afresh");
        assert_eq!(rate.sample(at(17_000), 37_000, false), 2000);
        assert_eq!(rate.sample(at(17_500), 100, false), 0, "a fall back starts again");
    }
}
