import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../helper_methods.dart';

/// Makes sure the desktop can find a `.desktop` file for Rift's app id.
///
/// The global-shortcuts portal will not talk to an unsandboxed app whose id
/// has no desktop entry — GNOME checks, and refuses with "An app id is
/// required". A package installs one; a build run from its folder has none,
/// so this writes one into the user's own applications directory.
///
/// Not hidden. GNOME Settings lists only visible entries, and its page for
/// Rift is the one place the push-to-talk key can be changed once the desktop
/// owns it — a `NoDisplay` entry made that page unreachable.
///
/// An entry this wrote before is rewritten for the AppImage, and when the
/// program it names is gone. An AppImage runs from a folder mounted afresh at
/// every start, so its entry names the AppImage file; and it is the copy that
/// stays, where a folder unpacked to try a build is not.
class LinuxDesktopEntry {
  const LinuxDesktopEntry._();

  /// Must match `APPLICATION_ID` in `linux/CMakeLists.txt`, which the runner
  /// hands GTK as the application id.
  static const appId = 'com.codingfries.rift';

  static Future<void> ensure() async {
    final fileName = '$appId.desktop';
    final home = Platform.environment['HOME'];
    final dataHome =
        Platform.environment['XDG_DATA_HOME'] ??
        (home == null ? null : p.join(home, '.local/share'));
    final own = dataHome == null
        ? null
        : File(p.join(dataHome, 'applications', fileName));
    final appImage = Platform.environment['APPIMAGE'];
    final wanted = entry(appImage ?? Platform.resolvedExecutable);
    for (final dir in _dataDirs()) {
      final file = File(p.join(dir, 'applications', fileName));
      if (!file.existsSync()) continue;
      if (file.path != own?.path) return;
      try {
        final current = await file.readAsString();
        if (current == wanted || !isOwnEntry(current)) return;
        final named = current.split('Exec=').last.trim();
        if (appImage == null && File(named).existsSync()) return;
      } catch (_) {
        return;
      }
      break;
    }
    if (own == null) return;
    try {
      await own.parent.create(recursive: true);
      await own.writeAsString(wanted);
    } catch (e) {
      HelperMethods.printDebug(
        'LinuxDesktopEntry: could not write $fileName – $e',
      );
    }
  }

  /// The entry this writes for the program at [executable].
  @visibleForTesting
  static String entry(String executable) =>
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=Rift\n'
      'Exec=$executable\n';

  /// Whether [content] is an entry this wrote, for whichever program — and
  /// not one a package or the person made, which is left alone.
  @visibleForTesting
  static bool isOwnEntry(String content) => RegExp(
    r'^\[Desktop Entry\]\nType=Application\nName=Rift\nExec=[^\n]*\n$',
  ).hasMatch(content);

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
