import 'package:flutter/foundation.dart';

/// Tracks whether the app window currently has OS focus.
///
/// Fed by the `WindowListener` callbacks in `main.dart` (window_manager). Chat
/// cubits read [isFocused] to decide whether an incoming message warrants an OS
/// notification — we never notify while the user is looking at the app.
///
/// [focused] is exposed as a [ValueListenable] so cubits can also react to
/// focus being *regained* — e.g. marking the open channel read when the user
/// returns to the window.
///
/// Defaults to focused: the window is visible and focused at launch, and on web
/// (where there are no window events) we simply never notify.
class WindowFocusService {
  WindowFocusService._();
  static final WindowFocusService instance = WindowFocusService._();

  final ValueNotifier<bool> focused = ValueNotifier<bool>(true);

  /// True while the window is focused (and not minimized).
  bool get isFocused => focused.value;

  void setFocused(bool value) {
    if (value == focused.value) return;
    if (kDebugMode) {
      // Cheap breadcrumb; focus transitions are rare.
      debugPrint('[WindowFocus] focused=$value');
    }
    focused.value = value;
  }
}
