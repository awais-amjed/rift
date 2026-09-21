import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Makes sure the desktop can find a `.desktop` file for Rift's app id.
///
/// The global-shortcuts portal will not talk to an unsandboxed app whose id
/// has no desktop entry — GNOME checks, and refuses with "An app id is
/// required". A package installs one; a build run from its folder has none,
/// so this writes a hidden one into the user's own applications directory.
/// Hidden, because its job is to say who the app is, not to add a launcher.
class LinuxDesktopEntry {
  const LinuxDesktopEntry._();

  /// Must match `APPLICATION_ID` in `linux/CMakeLists.txt`, which the runner
  /// hands GTK as the application id.
  static const appId = 'com.codingfries.rift';

  static Future<void> ensure() async {
    final fileName = '$appId.desktop';
    for (final dir in _dataDirs()) {
      if (File(p.join(dir, 'applications', fileName)).existsSync()) return;
    }
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final dataHome =
        Platform.environment['XDG_DATA_HOME'] ?? p.join(home, '.local/share');
    try {
      final file = File(p.join(dataHome, 'applications', fileName));
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Rift\n'
        'Exec=${Platform.resolvedExecutable}\n'
        'NoDisplay=true\n',
      );
    } catch (e) {
      debugPrint('LinuxDesktopEntry: could not write $fileName – $e');
    }
  }

  static List<String> _dataDirs() {
    final env = Platform.environment;
    final home = env['HOME'];
    return [
      env['XDG_DATA_HOME'] ??
          (home == null ? '' : p.join(home, '.local/share')),
      ...(env['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share').split(':'),
    ].where((d) => d.isNotEmpty).toList();
  }
}
