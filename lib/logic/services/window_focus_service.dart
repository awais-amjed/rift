import 'package:flutter/foundation.dart';

/// Tracks whether the app window currently has OS focus.
///
/// Fed by the `WindowListener` callbacks in `main.dart` (window_manager). Chat
/// cubits read [isFocused] to decide whether an incoming message warrants an OS
/// notification — we never notify while the user is looking at the app.
///
/// Defaults to focused: the window is visible and focused at launch, and on web
/// (where there are no window events) we simply never notify.
class WindowFocusService {
  WindowFocusService._();
  static final WindowFocusService instance = WindowFocusService._();

  bool _focused = true;

  /// True while the window is focused (and not minimized).
  bool get isFocused => _focused;

  void setFocused(bool value) {
    if (kDebugMode && value != _focused) {
      // Cheap breadcrumb; focus transitions are rare.
      debugPrint('[WindowFocus] focused=$value');
    }
    _focused = value;
  }
}
