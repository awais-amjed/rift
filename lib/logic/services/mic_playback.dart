/// Plays the mic test's own track back in the browser, behind a conditional
/// export. Windows and Linux play it back in the Rust library instead
/// (`rust/src/mic_test`), which reads the device itself.
///
/// The stub is what native compiles against, so nothing here reaches
/// `dart:js_interop` off the web.
library;

export 'mic_playback_stub.dart'
    if (dart.library.js_interop) 'mic_playback_web.dart';
