import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_window.dart';
import 'browser_apis.dart';
import 'host_platform.dart';

/// The whole app in full screen and back, for a stream watched full screen.
///
/// Each platform has its own idea of it: a desktop window covers the monitor,
/// a browser tab hides the browser, and a phone hides its status and
/// navigation bars until the user swipes them back.
class WindowFullscreen {
  const WindowFullscreen._();

  /// Whether full screen was asked for and not yet left. The window's size
  /// and position are not saved while it is — the next launch would
  /// otherwise open the size of the monitor — and the app's own title bar
  /// stands aside.
  static final ValueNotifier<bool> active = ValueNotifier(false);
  static bool get isOn => active.value;

  /// A stream watched edge to edge: it has the whole window, which keeps its
  /// size. The app's own title bar hides, and comes back while the pointer
  /// is at the top edge, so the window can still be moved and closed.
  static final ValueNotifier<bool> edgeToEdge = ValueNotifier(false);

  /// Called from a page's `initState` and `dispose`, in the middle of a
  /// frame, so all of it waits for a task of its own, after that frame.
  /// [AppWindow] calls the window directly, and the window answers a resize
  /// at once, re-entering Dart with the new size and a whole frame of its own
  /// while the frame that asked is still building. That left full screen
  /// black (frozen in a debug build) on Windows, whose Dart runs on the
  /// window's thread. [active] waits too: its listeners rebuild, which a
  /// build may not ask for.
  static Future<void> set(bool on) async {
    await Future<void>.delayed(Duration.zero);
    if (on) active.value = true;
    try {
      if (kIsWeb) {
        await setBrowserFullscreen(on);
      } else if (HostPlatform.isDesktop) {
        AppWindow.fullScreen = on;
      } else if (HostPlatform.isMobile) {
        await SystemChrome.setEnabledSystemUIMode(
          on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      }
    } finally {
      if (!on) active.value = false;
    }
  }
}
