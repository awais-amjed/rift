pub mod audio_endpoints;
pub mod blob_cipher;
pub mod cue;
pub mod logs;
pub mod mic_test;
pub mod noise_filter;
pub mod screenshare;
pub mod soundshare;
pub mod toast;
pub mod updater;

/// Runs once when Dart initialises the library, before any other call.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    crate::logging::init();
}
