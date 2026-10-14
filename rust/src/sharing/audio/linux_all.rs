//! Linux: every application's sound but Rift's, the way a whole-screen share
//! takes it on Windows.
//!
//! PulseAudio has no "everything but this process". A sink's monitor carries
//! what the sink plays, Rift's call included, and a call that hears itself
//! echoes. So each application's stream is recorded on its own, through a
//! monitor narrowed to it, as a single-application share does, and the
//! streams are mixed here. Applications that start playing after the share
//! began join it, and ones that stop leave it.
//!
//! Nothing here waits on the server. The streams already followed are read
//! on every turn, and a stall while a new one is looked up and opened was a
//! click in all the others — heard Oct 14 2026 as a 20 ms dip when a second
//! app started.
use super::linux::connect_stream;
use super::mixer::Mixer;
use super::pulse::{self, SinkInput};
use super::{samples_from_le_bytes, Command, Pcm};
use crate::pulse::Connection;
use libpulse_binding as pa;
use pa::callbacks::ListResult;
use pa::context::subscribe::{Facility, InterestMaskSet};
use pa::stream::{PeekResult, State, Stream};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, TryRecvError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tokio::sync::mpsc::Sender as FrameSender;

/// How often the streams playing may be listed again. A volume slider being
/// dragged changes its stream many times a second, and each change only
/// needs to be looked at once.
const RELIST_EVERY: Duration = Duration::from_millis(250);

/// One application's stream being recorded.
struct Followed {
    /// The sink it played to when it was opened. A stream moved to another
    /// device is opened again there, since its record stream does not move.
    sink: u32,
    stream: Stream,
}

pub(super) fn spawn_capture_thread(
    commands: Receiver<Command>,
    frames: FrameSender<Pcm>,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let Some(mut connection) = Connection::open("rift-screenshare-audio") else {
            return;
        };
        let changed = watch_sink_inputs(&mut connection);
        let rift = Rift::current();
        let mut followed: HashMap<u32, Followed> = HashMap::new();
        let mut mixer = Mixer::default();
        let mut listing: Option<Arc<Mutex<Listing>>> = None;
        let mut listed_at: Option<Instant> = None;
        log::info!("audio: capturing everything but Rift");
        'capture: loop {
            match commands.try_recv() {
                Ok(Command::Terminate) | Err(TryRecvError::Disconnected) => break,
                Err(TryRecvError::Empty) => {}
            }
            if !connection.turn() {
                log::warn!("audio: PulseAudio mainloop failed");
                break;
            }
            let due = listed_at.is_none_or(|at| at.elapsed() >= RELIST_EVERY);
            if listing.is_none() && due && changed.swap(false, Ordering::SeqCst) {
                listed_at = Some(Instant::now());
                listing = Some(Listing::ask(&mut connection));
            }
            let answer = listing.as_ref().and_then(|l| l.lock().unwrap().answer());
            if let Some(answer) = answer {
                listing = None;
                match answer {
                    Some((playing, monitors)) => {
                        let playing = playing.into_iter().filter(|input| !rift.plays(input));
                        follow(
                            &mut connection,
                            &mut followed,
                            &mut mixer,
                            playing,
                            &monitors,
                        );
                    }
                    // Asked again on the next turn it may be.
                    None => changed.store(true, Ordering::SeqCst),
                }
            }
            followed.retain(|&index, f| {
                let open = read(&mut f.stream, index, &mut mixer);
                if !open {
                    log::info!("audio: stopped following sink-input #{index}");
                    let _ = f.stream.disconnect();
                    mixer.remove(index);
                }
                open
            });
            while let Some(frame) = mixer.next_frame() {
                if frames.blocking_send(Pcm::read_now(frame)).is_err() {
                    break 'capture;
                }
            }
        }
        for (_, mut f) in followed {
            let _ = f.stream.disconnect();
        }
        log::info!("audio: capture thread exiting");
    })
}

/// Set whenever a stream starts, ends or changes, starting set so the first
/// turn lists what is already playing.
fn watch_sink_inputs(connection: &mut Connection) -> Arc<AtomicBool> {
    let changed = Arc::new(AtomicBool::new(true));
    let flag = Arc::clone(&changed);
    connection
        .context
        .set_subscribe_callback(Some(Box::new(move |facility, _, _| {
            if facility == Some(Facility::SinkInput) {
                flag.store(true, Ordering::SeqCst);
            }
        })));
    let _ = connection
        .context
        .subscribe(InterestMaskSet::SINK_INPUT, |_| {});
    changed
}

/// The streams playing and each sink's monitor, asked for together and
/// answered over later turns of the capture's own loop.
#[derive(Default)]
struct Listing {
    playing: Option<Vec<SinkInput>>,
    monitors: Option<HashMap<u32, String>>,
    failed: bool,
}

type Answer = Option<(Vec<SinkInput>, HashMap<u32, String>)>;

impl Listing {
    fn ask(connection: &mut Connection) -> Arc<Mutex<Listing>> {
        let listing = Arc::new(Mutex::new(Listing::default()));
        let introspect = connection.context.introspect();
        let (out, mut found) = (Arc::clone(&listing), Vec::new());
        let _ = introspect.get_sink_input_info_list(move |result| match result {
            ListResult::Item(info) => found.push(pulse::sink_input(info)),
            ListResult::End => out.lock().unwrap().playing = Some(std::mem::take(&mut found)),
            ListResult::Error => out.lock().unwrap().failed = true,
        });
        let (out, mut found) = (Arc::clone(&listing), HashMap::new());
        let _ = introspect.get_sink_info_list(move |result| match result {
            ListResult::Item(info) => {
                if let Some(monitor) = &info.monitor_source_name {
                    found.insert(info.index, monitor.to_string());
                }
            }
            ListResult::End => out.lock().unwrap().monitors = Some(std::mem::take(&mut found)),
            ListResult::Error => out.lock().unwrap().failed = true,
        });
        listing
    }

    /// Once both lists are in: them, or none if the server refused either.
    fn answer(&mut self) -> Option<Answer> {
        if self.failed {
            return Some(None);
        }
        if self.playing.is_none() || self.monitors.is_none() {
            return None;
        }
        Some(self.playing.take().zip(self.monitors.take()))
    }
}

/// Bring what is recorded in line with what is playing: open the streams
/// that are new, and close the ones that ended or moved to another device.
fn follow(
    connection: &mut Connection,
    followed: &mut HashMap<u32, Followed>,
    mixer: &mut Mixer,
    playing: impl Iterator<Item = SinkInput>,
    monitors: &HashMap<u32, String>,
) {
    let playing: HashMap<u32, u32> = playing
        .map(|input| (input.source.index, input.source.sink))
        .collect();
    followed.retain(|index, f| {
        let keep = playing.get(index) == Some(&f.sink);
        if !keep {
            let _ = f.stream.disconnect();
            mixer.remove(*index);
        }
        keep
    });
    for (&index, &sink) in &playing {
        if followed.contains_key(&index) {
            continue;
        }
        let Some(monitor) = monitors.get(&sink) else {
            continue;
        };
        if let Some(stream) = connect_stream(connection, index, monitor) {
            log::info!("audio: following sink-input #{index} on {monitor}");
            followed.insert(index, Followed { sink, stream });
        }
    }
}

/// Everything `stream` has waiting, into its lane. False once it can be read
/// no more; a stream still starting has nothing yet.
fn read(stream: &mut Stream, index: u32, mixer: &mut Mixer) -> bool {
    match stream.get_state() {
        State::Ready => {}
        State::Failed | State::Terminated => return false,
        _ => return true,
    }
    loop {
        match stream.peek() {
            Ok(PeekResult::Data(data)) => {
                mixer.push(index, &samples_from_le_bytes(data));
                let _ = stream.discard();
            }
            Ok(PeekResult::Hole(_)) => {
                let _ = stream.discard();
            }
            Ok(PeekResult::Empty) => return true,
            Err(e) => {
                log::warn!("audio: PulseAudio read failed: {e:?}");
                return false;
            }
        }
    }
}

/// How to tell Rift's own streams apart: this process, and any other copy of
/// Rift on the machine — a second profile is a call too.
struct Rift {
    pid: u32,
    binary: String,
}

impl Rift {
    fn current() -> Self {
        let binary = std::env::current_exe()
            .ok()
            .and_then(|path| path.file_name()?.to_str().map(str::to_lowercase))
            .unwrap_or_default();
        Self {
            pid: std::process::id(),
            binary,
        }
    }

    fn plays(&self, input: &SinkInput) -> bool {
        input.pid == Some(self.pid)
            || (!self.binary.is_empty() && input.source.binary.trim().to_lowercase() == self.binary)
    }
}
