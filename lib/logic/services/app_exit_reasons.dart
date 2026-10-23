import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

/// Why the app's last few runs on Android ended, written into this session's
/// log: a run killed for memory or stopped for an ANR leaves nothing in its
/// own, and a call's service killed in the background looks like a crash to
/// whoever it happened to. The native half is `ExitReasons.kt`
/// (`ApplicationExitInfo`, Android 11 and up); older Androids answer nothing.
class AppExitReasons {
  const AppExitReasons._();

  static const _channel = MethodChannel('rift/exit_reasons');

  /// Logs the recent endings, newest first. Never throws: a log that could
  /// not be added to is no reason to stop the start.
  static Future<void> log() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final exits = await _channel.invokeListMethod<Map>('recent') ?? const [];
      if (exits.isEmpty) {
        AppLog.write('Exit: Android kept no ending from the last 14 days');
      }
      for (final exit in exits) {
        AppLog.write('Exit: ${describe(exit.cast<String, Object?>())}');
      }
    } catch (e) {
      AppLog.write('Exit: Android did not say how the last runs ended – $e');
    }
  }

  /// One ending as a line: when, which run, why, and how it stood then.
  @visibleForTesting
  static String describe(Map<String, Object?> exit) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      (exit['timestamp'] as int?) ?? 0,
      isUtc: true,
    ).toIso8601String();
    final status = (exit['status'] as int?) ?? 0;
    final reason = (exit['reason'] as int?) ?? 0;
    final parts = <String>[
      _reason(reason, status),
      _importance((exit['importance'] as int?) ?? 0),
      if (((exit['pssKb'] as int?) ?? 0) > 0)
        '${(exit['pssKb'] as int) ~/ 1024} MB in use',
    ];
    final description = exit['description'] as String?;
    return 'run ${exit['pid']} (${exit['process']}) ended $at: '
        '${parts.join(', ')}'
        '${description == null || description.isEmpty ? '' : ' – $description'}';
  }

  /// `ApplicationExitInfo.REASON_*`. The status is an exit code for a run
  /// that ended itself, and a signal for one that was signalled.
  static String _reason(int reason, int status) => switch (reason) {
    1 => 'exited with code $status',
    2 => 'ended by signal $status',
    3 => 'killed for low memory',
    4 => 'crashed (Java)',
    5 => 'crashed in native code (signal $status)',
    6 => 'stopped for not responding (ANR)',
    7 => 'failed to start',
    8 => 'stopped for a permission change',
    9 => 'killed for using too much of the device',
    10 => 'stopped by the user',
    11 => 'force-stopped by the user',
    12 => 'stopped with a process it depended on',
    13 => 'stopped by the system',
    14 => 'stopped while frozen',
    15 => 'stopped for a change to the app',
    16 => 'stopped for an update',
    _ => 'ended for an unknown reason ($reason)',
  };

  /// `RunningAppProcessInfo.IMPORTANCE_*`: whether it was on screen.
  static String _importance(int importance) => switch (importance) {
    100 => 'on screen',
    125 => 'in a foreground service',
    200 => 'visible',
    230 => 'perceptible',
    300 => 'as a service',
    325 => 'on screen while the device slept',
    350 || 400 => 'in the background',
    _ => 'importance $importance',
  };
}
