import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

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

  static Future<void> set(bool on) async {
    if (on) active.value = true;
    try {
      if (kIsWeb) {
        await setBrowserFullscreen(on);
      } else if (HostPlatform.isDesktop) {
        await windowManager.setFullScreen(on);
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
