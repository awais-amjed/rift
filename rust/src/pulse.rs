//! The PulseAudio connection everything on Linux shares: the sound share,
//! the settings mic test and the device watcher. PipeWire's PulseAudio server
//! answers it the same way.
use libpulse_binding as pa;
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
