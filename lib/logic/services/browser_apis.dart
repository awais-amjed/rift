/// Browser-only capabilities, behind a conditional export.
///
/// Two things live here together because on the web they are one feature: a
/// notification is only worth showing when the tab is *not* the thing you are
/// looking at, so the notification API is useless without the focus signal that
/// gates it. On every other platform `window_manager` supplies that signal and
/// `flutter_local_notifications` supplies the notification, which is why this
/// pair exists only for the web half. Full screen is here for the same
/// reason: off the web, `window_manager` and the system UI modes do it.
///
/// The stub is what native compiles against, so nothing here reaches
/// `dart:js_interop` off the web.
library;

export 'browser_apis_stub.dart'
    if (dart.library.js_interop) 'browser_apis_web.dart';
