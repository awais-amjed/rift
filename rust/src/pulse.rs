//! The PulseAudio connection everything on Linux shares — the sound share,
//! the settings mic test, the device pickers and the device watcher — and the
//! device lists they read through it. PipeWire's PulseAudio server answers it
//! the same way.
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

/// A sink or source as the server lists it.
///
/// WebRTC's PulseAudio module gives a device no id, only its description, so
/// the description is the id everything on the Dart side holds; the name is
/// what the server itself is asked for.
pub(crate) struct Device {
    pub name: String,
    pub description: String,
    pub channels: u8,
    pub rate: u32,
}

/// Every sink, in the server's order, which is the order WebRTC lists them
/// in. Empty if the server does not answer.
pub(crate) fn sinks(connection: &mut Connection) -> Vec<Device> {
    let devices: Arc<Mutex<Vec<Device>>> = Arc::new(Mutex::new(Vec::new()));
    let done = Arc::new(Mutex::new(false));
    let (out, finished) = (Arc::clone(&devices), Arc::clone(&done));
    let _op = connection
        .context
        .introspect()
        .get_sink_info_list(move |result| match result {
            ListResult::Item(info) => out.lock().unwrap().push(Device {
                name: info.name.as_deref().unwrap_or_default().to_string(),
                description: info.description.as_deref().unwrap_or_default().to_string(),
                channels: info.sample_spec.channels,
                rate: info.sample_spec.rate,
            }),
            ListResult::End | ListResult::Error => *finished.lock().unwrap() = true,
        });
    if !connection.run_until(&done) {
        return Vec::new();
    }
    let list = std::mem::take(&mut *devices.lock().unwrap());
    list
}

/// Every source but the monitors, in the server's order. WebRTC leaves the
/// monitors out of its list, so a monitor is never a microphone it means.
pub(crate) fn sources(connection: &mut Connection) -> Vec<Device> {
    let devices: Arc<Mutex<Vec<Device>>> = Arc::new(Mutex::new(Vec::new()));
    let done = Arc::new(Mutex::new(false));
    let (out, finished) = (Arc::clone(&devices), Arc::clone(&done));
    let _op = connection
        .context
        .introspect()
        .get_source_info_list(move |result| match result {
            ListResult::Item(info) if info.monitor_of_sink.is_none() => {
                out.lock().unwrap().push(Device {
                    name: info.name.as_deref().unwrap_or_default().to_string(),
                    description: info.description.as_deref().unwrap_or_default().to_string(),
                    channels: info.sample_spec.channels,
                    rate: info.sample_spec.rate,
                })
            }
            ListResult::Item(_) => {}
            ListResult::End | ListResult::Error => *finished.lock().unwrap() = true,
        });
    if !connection.run_until(&done) {
        return Vec::new();
    }
    let list = std::mem::take(&mut *devices.lock().unwrap());
    list
}
