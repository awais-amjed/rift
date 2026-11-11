/// The browser's player for [ChatClip], behind a conditional export. The
/// stub is what native compiles against, so nothing here reaches
/// `dart:js_interop` off the web.
library;

export 'web_chat_clip_stub.dart'
    if (dart.library.js_interop) 'web_chat_clip_browser.dart';
