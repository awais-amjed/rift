//! Talking to PulseAudio (or PipeWire's PulseAudio server): connecting, and
//! the two introspection queries the share needs.
use crate::api::screenshare::types::AudioSource;
use libpulse_binding as pa;
use pa::callbacks::ListResult;
use pa::context::{Context, State};
use pa::mainloop::standard::Mainloop;
use pa::time::MicroSeconds;
use std::sync::{Arc, Mutex};

/// How long one bounded mainloop turn may block. Bounds how late a terminate
/// command is noticed when no audio is arriving.
const TURN: MicroSeconds = MicroSeconds(20_000);

/// A connected context and the mainloop that drives it. Disconnects on drop.
pub(crate) struct Connection {
    pub mainloop: Mainloop,
    pub context: Context,
}

impl Connection {
    /// Connect to the default server, or say why not. Returns once the
    /// context is ready, so callers can issue requests immediately.
    pub(crate) fn open(name: &str) -> Option<Connection> {
        let mut mainloop = Mainloop::new()?;
        let mut context = Context::new(&mainloop, name)?;
        if context
            .connect(None, pa::context::FlagSet::NOFLAGS, None)
            .is_err()
        {
            log::warn!("pulse: could not connect");
            return None;
        }
        loop {
            if mainloop.iterate(true).is_error() {
                return None;
            }
            match context.get_state() {
                State::Ready => break,
                State::Failed | State::Terminated => {
                    log::warn!("pulse: connection failed before it was ready");
                    return None;
                }
                _ => {}
            }
        }
        Some(Connection { mainloop, context })
    }

    /// One turn of the mainloop, waiting at most [`TURN`] for something to
    /// do. `iterate(true)` would wait indefinitely, and a monitor stream of a
    /// paused application delivers nothing to wait for.
    pub(crate) fn turn(&mut self) -> bool {
        if self.mainloop.prepare(Some(TURN)).is_err() || self.mainloop.poll().is_err() {
            return false;
        }
        self.mainloop.dispatch().is_ok()
    }

    /// Drive the loop until `done` is set. False if the server went away
    /// first, without which a lost server would spin here forever.
    pub(crate) fn run_until(&mut self, done: &Arc<Mutex<bool>>) -> bool {
        loop {
            if self.mainloop.iterate(true).is_error() {
                return false;
            }
            if *done.lock().unwrap() {
                return true;
            }
            if matches!(self.context.get_state(), State::Failed | State::Terminated) {
                log::warn!("pulse: connection failed while waiting for a reply");
                return false;
            }
        }
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        self.context.disconnect();
        self.mainloop.quit(pa::def::Retval(0));
    }
}

/// Every application stream currently playing.
pub(crate) fn list_sink_inputs() -> Vec<AudioSource> {
    let Some(mut connection) = Connection::open("rift-audio-list") else {
        return Vec::new();
    };
    let entries: Arc<Mutex<Vec<AudioSource>>> = Arc::new(Mutex::new(Vec::new()));
    let done = Arc::new(Mutex::new(false));
    let (out, finished) = (Arc::clone(&entries), Arc::clone(&done));
    let _op =
        connection
            .context
            .introspect()
            .get_sink_input_info_list(move |result| match result {
                ListResult::Item(info) => out.lock().unwrap().push(AudioSource {
                    index: info.index,
                    sink: info.sink,
                    app_name: info
                        .proplist
                        .get_str("application.name")
                        .unwrap_or_default(),
                    binary: info
                        .proplist
                        .get_str("application.process.binary")
                        .unwrap_or_default(),
                    media_name: info.proplist.get_str("media.name").unwrap_or_default(),
                }),
                ListResult::End | ListResult::Error => *finished.lock().unwrap() = true,
            });
    connection.run_until(&done);
    let list = entries.lock().unwrap().clone();
    list
}

/// The monitor source that carries what `sink_index` plays.
pub(crate) fn monitor_source_name(sink_index: u32) -> Option<String> {
    let mut connection = Connection::open("rift-audio-monitor")?;
    let name: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    let done = Arc::new(Mutex::new(false));
    let (out, finished) = (Arc::clone(&name), Arc::clone(&done));
    let _op = connection
        .context
        .introspect()
        .get_sink_info_by_index(sink_index, move |result| match result {
            ListResult::Item(info) => {
                if let Some(monitor) = &info.monitor_source_name {
                    *out.lock().unwrap() = Some(monitor.to_string());
                }
            }
            ListResult::End | ListResult::Error => *finished.lock().unwrap() = true,
        });
    connection.run_until(&done);
    let found = name.lock().unwrap().clone();
    found
}
