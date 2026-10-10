import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../src/rust/api/logs.dart' as rust;
import 'storage_namespace.dart';

/// The app's log, kept so someone can send it after something went wrong.
///
/// On desktop and Android the lines go to a file that Rust writes, beside its
/// own (`rust/src/logging.rs`): one per session in the profile's `logs`
/// folder, the newest few kept, and a crash in native code still leaves the
/// lines before it. The web has no file, so the last [_webLines] stay in
/// memory for this tab.
///
/// Lines logged before [start] wait in memory. So do the ones logged in an
/// isolate that never calls [start] (the push wake-up), which therefore keep
/// nothing past [_waitingLines].
class AppLog {
  const AppLog._();

  static const _webLines = 3000;
  static const _waitingLines = 500;

  static bool _started = false;
  static String? _path;
  static final Queue<String> _lines = Queue<String>();

  /// This session's file, once [start] has opened it.
  static String? get path => _path;

  /// The folder the profile's logs go in: the session files, and the ones
  /// before it.
  static Future<Directory> folder(String storageSuffix) async => Directory(
    '${await StorageNamespace.profileDirectory(storageSuffix)}/logs',
  );

  /// Opens this session's file and writes what waited for it. Call once the
  /// Rust bridge is up. On the web it only marks the log started.
  static Future<void> start(String storageSuffix) async {
    if (_started) return;
    if (kIsWeb) {
      _started = true;
      return;
    }
    try {
      final dir = await folder(storageSuffix);
      _path = await rust.startLogFile(dir: dir.path);
      _started = true;
      for (final line in _lines) {
        rust.writeLogLine(source: 'dart', line: line);
      }
      _lines.clear();
    } catch (e) {
      if (kDebugMode) print('AppLog: no log file – $e');
    }
  }

  /// Logs the errors nothing else caught: the framework's, and those thrown
  /// in a callback with no handler. Each still goes where it went before.
  static void catchErrors() {
    final framework = FlutterError.onError;
    FlutterError.onError = (details) {
      write(
        '${details.exceptionAsString()}\n${details.stack ?? ''}',
        source: 'flutter',
      );
      framework?.call(details);
    };
    final platform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      write('uncaught: $error\n$stack', source: 'flutter');
      return platform?.call(error, stack) ?? false;
    };
  }

  /// The version and the system, as the log's first line and a report's
  /// header give them: `1.4.0-beta.6+12`, `windows "Windows 10 Pro" 10.0 (Build 19045)`.
  static Future<({String version, String system})> about() async {
    final info = await PackageInfo.fromPlatform();
    final system = kIsWeb
        ? 'web'
        : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    return (version: '${info.version}+${info.buildNumber}', system: system);
  }

  /// Logs the version and the system, so every log says what it came from.
  static Future<void> writeHeader() async {
    try {
      final about = await AppLog.about();
      write('Rift ${about.version} on ${about.system}');
    } catch (e) {
      write('Rift, version unknown: $e');
    }
  }

  /// Logs one line from [source] (`dart` for [HelperMethods.printDebug],
  /// `flutter` for an uncaught error).
  static void write(String line, {String source = 'dart'}) {
    if (_started && !kIsWeb) {
      try {
        rust.writeLogLine(source: source, line: line);
      } catch (_) {
        // Nowhere left to say it.
      }
      return;
    }
    final stamped = kIsWeb
        ? '${DateTime.now().toUtc().toIso8601String()} $source: $line'
        : line;
    _lines.add(stamped);
    final cap = kIsWeb ? _webLines : _waitingLines;
    while (_lines.length > cap) {
      _lines.removeFirst();
    }
  }

  /// The web's lines, oldest first. Empty elsewhere once the file is open.
  static List<String> get memoryLines => List.unmodifiable(_lines);
}
