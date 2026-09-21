import 'dart:io';

import 'package:flutter/foundation.dart';

import 'linux_desktop_entry.dart';

/// Opens the desktop's own page for Rift's global shortcuts.
///
/// Once the desktop has granted a push-to-talk key it keeps it: binding again
/// with a different suggestion gets the old key back, and GNOME's portal has
/// no call for asking to change it. So the way to change the key is the page
/// where the desktop edits it — on GNOME, Settings → Apps → Rift → Global
/// Shortcuts, which `gnome-control-center applications <app id>` opens
/// directly. Other desktops have their own place and no verified way in, so
/// they get the sentence and not the button.
class DesktopShortcutSettings {
  const DesktopShortcutSettings._();

  static bool get canOpen {
    if (kIsWeb || !Platform.isLinux) return false;
    final desktop = Platform.environment['XDG_CURRENT_DESKTOP'] ?? '';
    return desktop.split(':').contains('GNOME');
  }

  static Future<void> open() async {
    try {
      await Process.start('gnome-control-center', [
        'applications',
        LinuxDesktopEntry.appId,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('DesktopShortcutSettings: could not open Settings – $e');
    }
  }
}
