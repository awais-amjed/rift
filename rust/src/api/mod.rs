pub mod audio_endpoints;
pub mod cue;
pub mod mic_test;
pub mod screenshare;
pub mod soundshare;

/// Runs once when Dart initialises the library, before any other call.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    crate::logging::init();
}
