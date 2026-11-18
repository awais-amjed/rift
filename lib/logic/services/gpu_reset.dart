import 'package:flutter/services.dart';

/// Rift starting itself again after the GPU its window draws with was reset.
///
/// A game that crashes the graphics driver, or closes badly enough that
/// Windows resets it, takes every Direct3D device on that GPU with it.
/// Flutter's renderer never makes a new one: the window stays white while the
/// call goes on underneath (report 03008880, Nov 18 2026). The Windows runner
/// hears the reset (`windows/runner/gpu_watch.h`) and starts a new copy that
/// takes over once this one has quit (`relaunch.h`); `GpuResetListener`
/// decides and quits.
class GpuReset {
  const GpuReset._();

  /// What the runner gives the new copy, so it can say why it started.
  static const flag = '--after-gpu-reset';

  static const MethodChannel channel = MethodChannel('rift/gpu');

  static bool _startedAfterReset = false;
  static final Stopwatch _sinceStart = Stopwatch();

  /// Whether this copy was started by the one before it, after a reset.
  static bool get startedAfterReset => _startedAfterReset;

  /// How long this copy has run.
  static Duration get sinceStart => _sinceStart.elapsed;

  /// Takes [flag] from the app's arguments. Call from `main`.
  static void readArguments(List<String> args) {
    _startedAfterReset = args.contains(flag);
    _sinceStart.start();
  }

  /// Starts the new copy, which waits for this one to quit. False when
  /// Windows would not start it, or there is no runner to ask.
  static Future<bool> relaunch() async {
    try {
      return await channel.invokeMethod<bool>('relaunch') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
