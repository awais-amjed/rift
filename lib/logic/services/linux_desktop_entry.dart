import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../helper_methods.dart';

/// Rift's entry in the desktop's app menu, `com.codingfries.rift.desktop`.
///
/// Two things need it. The AppImage is one file a person downloads and runs,
/// and nothing puts it in the app menu, so at every start it adds itself, with
/// its icon; the entry names the AppImage file, which an update replaces in
/// place. And the global-shortcuts portal will not talk to an unsandboxed app
/// whose id has no desktop entry — GNOME checks, and refuses with "An app id
/// is required" — so push-to-talk asks for one from a build run from its
/// folder too.
///
/// Not hidden. GNOME Settings lists only visible entries, and its page for
/// Rift is the one place the push-to-talk key can be changed once the desktop
/// owns it — a `NoDisplay` entry made that page unreachable.
///
/// An entry this wrote before is rewritten for the AppImage, and when the
/// program it names is gone. An AppImage runs from a folder mounted afresh at
/// every start, so its entry names the AppImage file; and it is the copy that
/// stays, where a folder unpacked to try a build is not. An entry a package or
/// the person wrote is left alone.
class LinuxDesktopEntry {
  const LinuxDesktopEntry._();

  /// Must match `APPLICATION_ID` in `linux/CMakeLists.txt`, which the runner
  /// hands GTK as the application id — the name the desktop matches a window
  /// to its entry by.
  static const appId = 'com.codingfries.rift';

  /// The line that marks an entry as this one's to rewrite.
  static const _marker = 'X-Rift-Written=true';

  static Future<void> ensure() async {
    final fileName = '$appId.desktop';
    final dataHome = _dataHome();
    final own = dataHome == null
        ? null
        : File(p.join(dataHome, 'applications', fileName));
    final appImage = Platform.environment['APPIMAGE'];
    final withIcon =
        appImage != null && dataHome != null && await _installIcon(dataHome);
    final wanted = entry(
      appImage ?? Platform.resolvedExecutable,
      withIcon: withIcon,
    );
    for (final dir in _dataDirs()) {
      final file = File(p.join(dir, 'applications', fileName));
      if (!file.existsSync()) continue;
      if (file.path != own?.path) return;
      try {
        final current = await file.readAsString();
        if (current == wanted || !isOwnEntry(current)) return;
        final named = execOf(current);
        if (appImage == null && named != null && File(named).existsSync()) {
          return;
        }
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

  /// Copies the AppImage's own icon (its `.DirIcon`, which vpk makes from
  /// `linux/packaging/rift.png`) into the person's icon theme, where the entry
  /// finds it by name. False when there is none to copy.
  static Future<bool> _installIcon(String dataHome) async {
    final appDir = Platform.environment['APPDIR'];
    if (appDir == null) return false;
    try {
      final source = File(p.join(appDir, '.DirIcon'));
      if (!source.existsSync()) return false;
      final bytes = await source.readAsBytes();
      final target = File(
        p.join(dataHome, 'icons/hicolor/256x256/apps', '$appId.png'),
      );
      if (target.existsSync() &&
          listEquals(await target.readAsBytes(), bytes)) {
        return true;
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes);
      return true;
    } catch (e) {
      HelperMethods.printDebug('LinuxDesktopEntry: icon – $e');
      return false;
    }
  }

  /// The entry this writes for the program at [executable].
  @visibleForTesting
  static String entry(String executable, {bool withIcon = false}) =>
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=Rift\n'
      'Comment=Voice, video and chat\n'
      'Exec=${_quoteExec(executable)}\n'
      '${withIcon ? 'Icon=$appId\n' : ''}'
      'Terminal=false\n'
      'Categories=Network;InstantMessaging;Chat;\n'
      'StartupWMClass=$appId\n'
      '$_marker\n';

  /// Whether [content] is an entry this wrote, for whichever program — and
  /// not one a package or the person made, which is left alone. Before the
  /// marker, this wrote only the four lines the pattern matches.
  @visibleForTesting
  static bool isOwnEntry(String content) =>
      content.split('\n').contains(_marker) ||
      RegExp(
        r'^\[Desktop Entry\]\nType=Application\nName=Rift\nExec=[^\n]*\n$',
      ).hasMatch(content);

  /// The program an entry's `Exec` line names, unquoted.
  @visibleForTesting
  static String? execOf(String content) {
    for (final line in content.split('\n')) {
      if (!line.startsWith('Exec=')) continue;
      final value = line.substring('Exec='.length).trim();
      if (!value.startsWith('"')) return value.split(' ').first;
      final end = value.indexOf(RegExp(r'(?<!\\)"'), 1);
      if (end < 0) return null;
      return value
          .substring(1, end)
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    }
    return null;
  }

  /// A path as the desktop entry spec wants it in `Exec`: quoted when it has
  /// anything but plain characters, with `"`, `` ` ``, `$` and `\` escaped
  /// inside the quotes.
  static String _quoteExec(String path) {
    if (RegExp(r'^[A-Za-z0-9_./+-]+$').hasMatch(path)) return path;
    final escaped = path.replaceAllMapped(
      RegExp(r'["`$\\]'),
      (m) => '\\${m[0]}',
    );
    return '"$escaped"';
  }

  static String? _dataHome() {
    final env = Platform.environment;
    final home = env['HOME'];
    return env['XDG_DATA_HOME'] ??
        (home == null ? null : p.join(home, '.local/share'));
  }

  static List<String> _dataDirs() => [
    ?_dataHome(),
    ...(Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':'),
  ].where((d) => d.isNotEmpty).toList();
}
