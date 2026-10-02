//! Linux: telling Dart when an audio device comes or goes, or the default
//! changes. Why WebRTC does not is in `api::audio_endpoints`.

use crate::frb_generated::StreamSink;
use crate::pulse::Connection;
use libpulse_binding as pa;
use pa::context::subscribe::{Facility, InterestMaskSet, Operation};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

/// How long the server has to go quiet before one change is reported. A
/// headset arriving is a sink, a source, a card and a default change within a
/// few milliseconds, and each would otherwise send Dart off to read the lists.
const SETTLE: Duration = Duration::from_millis(250);

pub(crate) fn start(sink: StreamSink<()>) {
    thread::spawn(move || {
        let Some(mut connection) = Connection::open("rift-device-watch") else {
            let _ = sink.add_error("could not reach the sound server".to_string());
            return;
        };
        let changed = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&changed);
        connection
            .context
            .set_subscribe_callback(Some(Box::new(move |facility, operation, _| {
                if is_device_change(facility, operation) {
                    flag.store(true, Ordering::Relaxed);
                }
            })));
        let _op = connection.context.subscribe(
            InterestMaskSet::SINK | InterestMaskSet::SOURCE | InterestMaskSet::SERVER,
            |_| {},
        );

        let mut pending_since: Option<Instant> = None;
        loop {
            if !connection.turn() {
                log::warn!("device watch: the sound server went away");
                let _ = sink.add_error("the sound server went away".to_string());
                return;
            }
            if changed.swap(false, Ordering::Relaxed) {
                pending_since = Some(Instant::now());
            }
            if pending_since.is_some_and(|since| since.elapsed() >= SETTLE) {
                pending_since = None;
                // Dart stopped listening: nothing left to watch for.
                if sink.add(()).is_err() {
                    return;
                }
            }
        }
    });
}

/// Whether an event changes what the pickers list or what "System default"
/// means. A device's own changes are left out: a sink reports one for every
/// volume step, and none of them adds or removes anything. The server's
/// changes are kept, since that is how a new default arrives.
fn is_device_change(facility: Option<Facility>, operation: Option<Operation>) -> bool {
    match facility {
        Some(Facility::Sink | Facility::Source) => {
            matches!(operation, Some(Operation::New | Operation::Removed))
        }
        Some(Facility::Server) => true,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn devices_arriving_and_leaving_count() {
        for facility in [Facility::Sink, Facility::Source] {
            assert!(is_device_change(Some(facility), Some(Operation::New)));
            assert!(is_device_change(Some(facility), Some(Operation::Removed)));
        }
    }

    #[test]
    fn a_volume_step_does_not() {
        assert!(!is_device_change(
            Some(Facility::Sink),
            Some(Operation::Changed)
        ));
        assert!(!is_device_change(
            Some(Facility::Source),
            Some(Operation::Changed)
        ));
    }

    #[test]
    fn a_new_default_does() {
        assert!(is_device_change(
            Some(Facility::Server),
            Some(Operation::Changed)
        ));
    }

    #[test]
    fn application_streams_do_not() {
        assert!(!is_device_change(
            Some(Facility::SinkInput),
            Some(Operation::New)
        ));
        assert!(!is_device_change(
            Some(Facility::SourceOutput),
            Some(Operation::Removed)
        ));
    }
}
