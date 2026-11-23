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

/// How long a connection or a server's first answer may take, and how long
/// a read may wait for the next bytes: a connection that died without a word
/// (the laptop slept, the network changed) otherwise left the read waiting
/// for ever, and the download on its last count until Rift was restarted.
const ANSWER_WAIT: Duration = Duration::from_secs(30);

/// How many times in a row a cut connection is asked again for the rest
/// before the download gives up; any bytes coming in start the count again.
const RETRIES: u32 = 4;

/// The wait before asking again after a cut.
const RETRY_AFTER: Duration = Duration::from_secs(2);

/// One read: small enough that a pause or cancel is felt at once.
const PIECE: usize = 64 * 1024;

/// What the speed is averaged over.
const RATE_WINDOW: Duration = Duration::from_secs(3);

pub(crate) struct Transfer {
    state: Mutex<State>,
    changed: Condvar,
    /// [ANSWER_WAIT] and [RETRY_AFTER], shorter in the tests.
    read_wait: Duration,
    retry_after: Duration,
}

/// A failure that asking again may get past: no connection, a quiet or cut
/// one, a name that would not resolve while the network came back, a
/// server's passing error.
fn is_cut(error: &ureq::Error) -> bool {
    matches!(
        error,
        ureq::Error::Io(_)
            | ureq::Error::Timeout(_)
            | ureq::Error::ConnectionFailed
            | ureq::Error::HostNotFound
            | ureq::Error::BodyStalled
    ) || matches!(error, ureq::Error::StatusCode(code) if (500..600).contains(code))
}

#[derive(Default)]
struct State {
    /// The download each was asked during ([Transfer::ask]), so starting a
    /// download clears what the one before it was asked and nothing later.
    paused: Option<u64>,
    cancelled: Option<u64>,
    /// The downloads asked for so far.
    asked: u64,
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
        Transfer {
            state: Mutex::new(State::default()),
            changed: Condvar::new(),
            read_wait: ANSWER_WAIT,
            retry_after: RETRY_AFTER,
        }
    }

    #[cfg(test)]
    fn quick(read_wait: Duration) -> Self {
        Transfer {
            read_wait,
            retry_after: Duration::from_millis(10),
            ..Transfer::new()
        }
    }

    /// Counts a download asked for, and returns its number for [plan]. Made
    /// when the person asks, which can be while the download before is still
    /// ending: a pause or cancel from then on is this one's.
    pub(crate) fn ask(&self) -> u64 {
        let mut state = self.state.lock().unwrap();
        state.asked += 1;
        state.asked
    }

    /// Starts download `asked` of `packages` over: nothing down, and neither
    /// paused nor cancelled by anything asked before it.
    pub(crate) fn plan(&self, asked: u64, packages: &[&VelopackAsset]) {
        let mut state = self.state.lock().unwrap();
        *state = State {
            planned: packages.iter().map(|p| p.FileName.clone()).collect(),
            total: packages.iter().map(|p| p.Size).sum(),
            paused: state.paused.filter(|&at| at >= asked),
            cancelled: state.cancelled.filter(|&at| at >= asked),
            asked: state.asked,
            ..State::default()
        };
        self.changed.notify_all();
    }

    pub(crate) fn pause(&self) {
        let mut state = self.state.lock().unwrap();
        state.paused = Some(state.asked);
        self.changed.notify_all();
    }

    pub(crate) fn resume(&self) {
        self.state.lock().unwrap().paused = None;
        self.changed.notify_all();
    }

    pub(crate) fn cancel(&self) {
        let mut state = self.state.lock().unwrap();
        state.cancelled = Some(state.asked);
        self.changed.notify_all();
    }

    /// Bytes down and bytes in all, and whether it is paused.
    pub(crate) fn progress(&self) -> (u64, u64, bool) {
        let state = self.state.lock().unwrap();
        (state.done, state.total, state.paused.is_some())
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
        if state.cancelled.is_some() {
            Some(Stop::Cancel)
        } else if state.paused.is_some() {
            Some(Stop::Pause)
        } else {
            None
        }
    }

    /// Waits out a pause; an error once cancelled.
    fn wait_unpaused(&self) -> Result<(), Error> {
        let mut state = self.state.lock().unwrap();
        while state.paused.is_some() && state.cancelled.is_none() {
            state = self.changed.wait(state).unwrap();
        }
        if state.cancelled.is_some() {
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
        let config = ureq::Agent::config_builder()
            .timeout_connect(Some(ANSWER_WAIT))
            .timeout_recv_response(Some(ANSWER_WAIT))
            .timeout_per_read(Some(self.read_wait));
        // The tests' server is on this machine, where a proxy named in the
        // environment cannot reach it.
        #[cfg(test)]
        let config = if url.starts_with("http://127.0.0.1") {
            config.proxy(None)
        } else {
            config
        };
        let agent: ureq::Agent = config.build().into();
        let mut file = File::create(path)?;
        let mut have: u64 = 0;
        let mut buffer = vec![0; PIECE];
        // Cuts in a row with nothing coming in between.
        let mut cuts = 0;
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
            let response = match request.call() {
                Ok(response) => response,
                Err(e) if cuts < RETRIES && is_cut(&e) => {
                    cuts += 1;
                    log::warn!("updater: asking again after {e}");
                    self.wait_for_retry(self.retry_after)?;
                    continue;
                }
                Err(e) => return Err(e.into()),
            };
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
                let read = match body.read(&mut buffer) {
                    Ok(read) => read,
                    // A connection that went quiet or was cut mid-file: the
                    // rest is asked for again, from where it got to.
                    Err(e) if cuts < RETRIES => {
                        cuts += 1;
                        log::warn!("updater: asking again for the rest after {e}");
                        self.wait_for_retry(self.retry_after)?;
                        break;
                    }
                    Err(e) => return Err(e.into()),
                };
                if read == 0 {
                    // Ended early, as a cut connection can: the size is
                    // known, so the rest is asked for.
                    if have < size && cuts < RETRIES {
                        cuts += 1;
                        log::warn!("updater: the connection ended at {have} of {size} bytes");
                        self.wait_for_retry(self.retry_after)?;
                        break;
                    }
                    return Ok(());
                }
                cuts = 0;
                file.write_all(&buffer[..read])?;
                have += read as u64;
                self.add(read as u64);
            }
        }
    }

    /// Waits `wait` before asking again, or less once cancelled.
    fn wait_for_retry(&self, wait: Duration) -> Result<(), Error> {
        let state = self.state.lock().unwrap();
        let (state, _) = self
            .changed
            .wait_timeout_while(state, wait, |s| s.cancelled.is_none())
            .unwrap();
        if state.cancelled.is_some() {
            Err(Error::Other(CANCELLED.to_string()))
        } else {
            Ok(())
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
        VelopackAsset {
            FileName: name.into(),
            Size: size,
            ..Default::default()
        }
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
                let from = if ranges {
                    range.and_then(|r| r.parse::<usize>().ok()).unwrap_or(0)
                } else {
                    0
                };
                let status = if from > 0 {
                    "206 Partial Content"
                } else {
                    "200 OK"
                };
                let head = format!(
                    "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    data.len() - from
                );
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
        let path =
            std::env::temp_dir().join(format!("rift-transfer-{}-{name}", std::process::id()));
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
        transfer.plan(transfer.ask(), &[&pkg]);
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
        transfer.plan(transfer.ask(), &[&pkg]);
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
        assert_eq!(
            lowest, held,
            "the resume carried on rather than starting again"
        );
        assert_eq!(std::fs::metadata(&path).unwrap().len(), size);
    }

    #[test]
    fn a_server_without_ranges_starts_over() {
        let bytes = data(300 * 1024);
        let (url, asked) = serve(bytes.clone(), false);
        let path = scratch("over");
        let transfer = Arc::new(Transfer::new());
        let pkg = asset("pkg", bytes.len() as u64);
        transfer.plan(transfer.ask(), &[&pkg]);
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
        transfer.plan(transfer.ask(), &[&pkg]);
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
        assert!(transfer
            .fetch("http://127.0.0.1:9/never", &pkg, &path)
            .is_err());
    }

    /// A server of `data` that sends the first request half of it and then
    /// goes quiet with the connection open, as one does when the network
    /// under it changes, and answers later requests from their `Range`.
    fn serve_stalling(data: Vec<u8>) -> (String, Arc<Mutex<Vec<Option<String>>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/pkg", listener.local_addr().unwrap());
        let asked = Arc::new(Mutex::new(Vec::new()));
        let log = asked.clone();
        std::thread::spawn(move || {
            let mut held = Vec::new();
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
                let first = log.lock().unwrap().is_empty();
                log.lock().unwrap().push(range.clone());
                let from = range.and_then(|r| r.parse::<usize>().ok()).unwrap_or(0);
                let status = if from > 0 {
                    "206 Partial Content"
                } else {
                    "200 OK"
                };
                let head = format!(
                    "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    data.len() - from
                );
                let _ = stream.write_all(head.as_bytes());
                if first {
                    let _ = stream.write_all(&data[..data.len() / 2]);
                    // Never closed: the read on the other end waits.
                    held.push(stream);
                } else {
                    let _ = stream.write_all(&data[from..]);
                }
            }
        });
        (url, asked)
    }

    #[test]
    fn a_connection_gone_quiet_is_asked_again_for_the_rest() {
        let bytes = data(200 * 1024);
        let (url, asked) = serve_stalling(bytes.clone());
        let path = scratch("stall");
        let transfer = Transfer::quick(Duration::from_millis(300));
        let pkg = asset("pkg", bytes.len() as u64);
        transfer.plan(transfer.ask(), &[&pkg]);
        transfer.fetch(&url, &pkg, &path).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
        assert_eq!(transfer.progress().0, bytes.len() as u64);
        let asked = asked.lock().unwrap();
        assert_eq!(asked.len(), 2);
        assert_eq!(
            asked[1].as_deref(),
            Some((bytes.len() / 2).to_string().as_str())
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn starting_a_download_keeps_what_was_asked_of_it_before_it_started() {
        let transfer = Transfer::new();
        // The last download, cancelled, is still ending when the next is
        // asked for, and paused before it gets going.
        transfer.cancel();
        let next = transfer.ask();
        transfer.pause();
        transfer.plan(next, &[&asset("pkg", 10)]);
        assert_eq!(transfer.stop(), Some(Stop::Pause));
        // Asked for again and started with nothing pressed since.
        transfer.cancel();
        let again = transfer.ask();
        transfer.plan(again, &[&asset("pkg", 10)]);
        assert_eq!(transfer.stop(), None);
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
        transfer.plan(transfer.ask(), &[&d1, &d2]);
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
        assert_eq!(
            rate.sample(at(500), 500, false),
            0,
            "under a second is no measure"
        );
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
        assert_eq!(
            rate.sample(at(16_000), 35_000, false),
            0,
            "a resume measures afresh"
        );
        assert_eq!(rate.sample(at(17_000), 37_000, false), 2000);
        assert_eq!(
            rate.sample(at(17_500), 100, false),
            0,
            "a fall back starts again"
        );
    }
}
