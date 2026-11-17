import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nativeapi/nativeapi.dart' show Application, DisplayManager;
import 'package:window_manager/window_manager.dart';

import 'gtk_window_size.dart';

/// Rift's one desktop window, through window_manager's native API
/// (nativeapi).
///
/// Every call reaches the window directly over FFI from Dart's thread, which
/// is why Dart runs on the window's own thread on Windows
/// (`windows/runner/main.cpp`): from a thread of its own, calls into a window
/// another thread owns are the mismatch that left tray_manager's icon deaf to
/// clicks there.
///
/// Where there is no window — a phone, the web, a widget test, whose Dart VM
/// has no native library to look the symbols up in — every call does nothing
/// and every question answers null.
abstract final class AppWindow {
  static Window? _window;

  static Window? get _target => _window ??= _tryNative<Window?>(
    () => WindowManager.instance.getCurrent(),
  );

  static ListenerId? _listener;

  static bool get _isLinux => !kIsWeb && Platform.isLinux;

  static final _events = StreamController<WindowEvent>.broadcast(sync: true);

  /// Whether a close request — the desktop's close, Alt+F4, the taskbar's
  /// Close — is refused, so the one hearing [WindowCloseRequestedEvent] on
  /// [events] decides what closing means.
  static bool _keepOpen = false;

  /// The window's events: focus, minimise, restore, move, resize, maximise,
  /// and close requests.
  static Stream<WindowEvent> get events {
    _listen();
    return _events.stream;
  }

  /// One native listener for the whole app, refusing a close before anyone
  /// hears of it while [keepOpenOnClose] is on.
  static void _listen() {
    if (_listener != null) return;
    final window = _target;
    if (window == null) return;
    _listener = _tryNative(
      () => window.addListener((event) {
        if (event is WindowCloseRequestedEvent && _keepOpen) {
          event.request.cancel();
        }
        _events.add(event);
      }),
    );
  }

  static set keepOpenOnClose(bool on) {
    _keepOpen = on;
    if (on) _listen();
  }

  /// The start-up shape: Rift draws its own title bar, at [size] and
  /// [position] (where the platform's runner put it, if null).
  static void setUp({
    required Size size,
    required Size minimumSize,
    Offset? position,
  }) {
    final window = _target;
    if (window == null) return;
    // On Linux the runner hides GTK's title bar (my_application.cc), and the
    // size is GTK's own, as [size] reads it.
    if (!_isLinux || !setGtkWindowSize(window.nativeObject, size)) {
      window.titleBarStyle = TitleBarStyle.hidden;
      window.contentSize = size.toNative();
    }
    window.minimumSize = minimumSize.toNative();
    if (position != null) window.position = position.toNative();
  }

  /// On screen and in front, from minimised, hidden to the tray, or behind
  /// another window.
  static void showAndFocus() {
    final window = _target;
    if (window == null) return;
    if (window.isMinimized) window.restore();
    window.show();
    window.focus();
  }

  /// Shown on the taskbar, minimised.
  static void showMinimized() {
    final window = _target;
    if (window == null) return;
    window.show();
    window.minimize();
  }

  static void hide() => _target?.hide();

  static void minimize() => _target?.minimize();

  static void maximize() => _target?.maximize();

  static void unmaximize() => _target?.unmaximize();

  static bool get isMaximized => _target?.isMaximized ?? false;

  static set fullScreen(bool on) => _target?.isFullScreen = on;

  /// The size [setUp] takes. On Linux GTK's own, as window_manager 0.5 read
  /// and set it: nativeapi's content size there is read right but set off by
  /// what it counts as decorations, so a size saved and restored through it
  /// grew or shrank at every start. Elsewhere the size inside the frame.
  static Size? get size {
    final window = _target;
    if (window == null) return null;
    if (_isLinux) {
      final gtk = gtkWindowSize(window.nativeObject);
      if (gtk != null) return gtk;
    }
    return window.contentSize.toSize();
  }

  static Offset? get position =>
      _tryNative<Offset?>(() => _target?.position.toOffset());

  /// Closes the window past [keepOpenOnClose], which ends the app once the
  /// runner sees its last window go: on Windows through WM_DESTROY, which
  /// shuts the engine down while the message loop still runs.
  static void close() {
    _keepOpen = false;
    final window = _target;
    final closing =
        window != null &&
        (_tryNative(() => Window.isCloseSupported() && window.close()) ??
            false);
    if (!closing) _tryNative(() => Application.instance.quit(0));
  }

  /// The displays' usable areas and the primary one's, or null when the
  /// platform won't say.
  static ({List<Rect> all, Rect primary})? workAreas() =>
      _tryNative<({List<Rect> all, Rect primary})?>(() {
        final displays = DisplayManager.instance.getAll();
        final primary = DisplayManager.instance.getPrimary();
        if (displays.isEmpty || primary == null) return null;
        return (
          all: [for (final d in displays) d.workArea.toRect()],
          primary: primary.workArea.toRect(),
        );
      });

  /// [body]'s answer, or null where the native library is not there to
  /// answer: a test's Dart VM looks the symbol up and throws, and the web's
  /// stand-in throws on every call.
  static T? _tryNative<T>(T Function() body) {
    try {
      return body();
    } on ArgumentError {
      return null;
    } on UnsupportedError {
      return null;
    }
  }
}
