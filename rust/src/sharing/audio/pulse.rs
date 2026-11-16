//! The introspection queries the share needs, over the connection in
//! `crate::pulse`.
use crate::api::screenshare::types::AudioSource;
use crate::pulse::Connection;
use libpulse_binding as pa;
use pa::callbacks::ListResult;
use pa::context::introspect::SinkInputInfo;
use std::sync::{Arc, Mutex};

/// Every application stream currently playing. Empty if the server does not
/// answer.
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
                ListResult::Item(info) => out.lock().unwrap().push(sink_input(info)),
                ListResult::End | ListResult::Error => *finished.lock().unwrap() = true,
            });
    if !connection.run_until(&done) {
        return Vec::new();
    }
    let list = std::mem::take(&mut *entries.lock().unwrap());
    list
}

pub(crate) fn sink_input(info: &SinkInputInfo) -> AudioSource {
    let get = |key: &str| info.proplist.get_str(key).unwrap_or_default();
    let app_id = Some(get("application.id"))
        .filter(|id| !id.is_empty())
        .unwrap_or_else(|| get("application.icon_name"));
    AudioSource {
        index: info.index,
        sink: info.sink,
        app_name: get("application.name"),
        binary: get("application.process.binary"),
        media_name: get("media.name"),
        app_id,
        pid: get("application.process.id").parse().ok(),
        playing: true,
    }
}
