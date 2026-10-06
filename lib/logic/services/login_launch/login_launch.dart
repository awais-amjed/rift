import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../helper_methods.dart';
import '../linux_desktop_entry.dart';
import '../storage_namespace.dart';
import 'run_key.dart';

/// Starting Rift when the person signs in to their computer, on Windows and
/// Linux.
///
/// Windows starts what its `Run` key names (`HKCU\…\CurrentVersion\Run`);
/// Linux desktops start what `~/.config/autostart` holds. Either is rewritten
/// at every start ([apply]), so it follows the program if it moves — the
/// AppImage's entry names the AppImage file, and Velopack keeps the Windows
/// program at the same path across updates. Uninstalling removes the Windows
/// value (`windows/runner/velopack_hooks.cpp`); the Linux entry carries
/// `TryExec`, so a deleted copy's entry is skipped rather than failing.
///
/// Each identity keeps its own entry, and only the person's own one starts
/// on by default: a `RIFT_PROFILE` copy is a second identity for testing,
/// which must not take the login over until someone asks it to.
class LoginLaunch {
  const LoginLaunch._();

  /// What the entry passes when Rift should start out of sight. The runners
  /// read it too, and then never show the window — it waits in the tray.
  static const minimizedFlag = '--minimized';

  static bool _startedMinimized = false;

  /// Whether this start was asked to stay out of sight.
  static bool get startedMinimized => _startedMinimized;

  /// Takes [minimizedFlag] from the app's arguments. Call from `main`.
  static void readArguments(List<String> args) {
    _startedMinimized = args.contains(minimizedFlag);
  }

  /// Not for a debug build run as the default identity: its entry would have
  /// the installed copy's name, and replace or remove that one.
  static bool get supported =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux) &&
      (kReleaseMode || StorageNamespace.explicitProfile != null);

  /// Whether starting at sign-in is on before anyone chooses: for the
  /// person's own installed copy, not a test profile or a debug build.
  static bool get onByDefault =>
      kReleaseMode && StorageNamespace.explicitProfile == null;

  /// Makes the computer start Rift at sign-in, or stop. Never throws: a
  /// failure costs the setting, not the app.
  static Future<void> apply({
    required bool enabled,
    required bool minimized,
  }) async {
    if (!supported) return;
    final profile = StorageNamespace.explicitProfile;
    final args = [
      if (profile != null) '--rift-profile=$profile',
      if (minimized) minimizedFlag,
    ];
    try {
      if (Platform.isWindows) {
        final name = profile == null ? 'Rift' : 'Rift.$profile';
        if (enabled) {
          setRunValue(name, runCommand(Platform.resolvedExecutable, args));
        } else {
          deleteRunValue(name);
        }
      } else {
        final file = _autostartFile(profile);
        if (file == null) return;
        if (enabled) {
          final wanted = autostartEntry(LinuxDesktopEntry.program, args);
          if (file.existsSync() && await file.readAsString() == wanted) return;
          await file.parent.create(recursive: true);
          await file.writeAsString(wanted);
        } else if (file.existsSync()) {
          await file.delete();
        }
      }
    } catch (e) {
      HelperMethods.printDebug('LoginLaunch: $e');
    }
  }

  /// The command the `Run` value holds: the program quoted, then [args].
  @visibleForTesting
  static String runCommand(String executable, List<String> args) =>
      ['"$executable"', ...args].join(' ');

  /// The autostart entry for [executable]. `TryExec` makes a desktop skip
  /// the entry once the program is gone, instead of failing at every login.
  @visibleForTesting
  static String autostartEntry(String executable, List<String> args) =>
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=Rift\n'
      'Comment=Voice, video and chat\n'
      'Exec=${[LinuxDesktopEntry.quoteExec(executable), ...args].join(' ')}\n'
      'TryExec=$executable\n'
      'Icon=${LinuxDesktopEntry.appId}\n'
      'Terminal=false\n'
      'X-GNOME-Autostart-enabled=true\n';

  static File? _autostartFile(String? profile) {
    final env = Platform.environment;
    final home = env['HOME'];
    final config =
        env['XDG_CONFIG_HOME'] ??
        (home == null ? null : p.join(home, '.config'));
    if (config == null) return null;
    final id = profile == null
        ? LinuxDesktopEntry.appId
        : '${LinuxDesktopEntry.appId}.$profile';
    return File(p.join(config, 'autostart', '$id.desktop'));
  }
}
