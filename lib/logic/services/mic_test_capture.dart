import 'package:livekit_client/livekit_client.dart';

import 'level_throttle.dart';
import 'pcm_level.dart';

/// Opens a microphone of its own and reports its level, for the mic test in
/// settings when no call already holds the device.
///
/// Deliberately the same measurement as the one running during a call — raw
/// PCM through [PcmLevel] — so the meter reads the same whether it is watching
/// its own capture or borrowing the call's. Two different units behind one bar
/// is how the threshold marker came to mean nothing.
class MicTestCapture {
  /// Matches the tap the call uses: mono and 16 kHz, which is ample for a
  /// level and a third of the platform-channel traffic of the mic's own rate.
  static const _rendererOptions = AudioRendererOptions(
    sampleRate: 16000,
    channels: 1,
    format: AudioFormat.Int16,
  );

  final LevelThrottle _throttle = LevelThrottle();

  LocalAudioTrack? _track;
  CancelListenFunc? _cancelRenderer;

  bool get isRunning => _track != null;

  /// Opens the microphone with [options] and calls [onLevel] as it runs.
  ///
  /// Throws if the device cannot be opened, having released anything it
  /// managed to acquire first.
  Future<void> start({
    required AudioCaptureOptions options,
    required void Function(double level) onLevel,
  }) async {
    if (_track != null) return;
    _throttle.reset();

    LocalAudioTrack? track;
    try {
      track = await LocalAudioTrack.create(options);
      _cancelRenderer = track.addAudioRenderer(
        onFrame: (frame) {
          final level = _throttle.add(
            PcmLevel.fromInt16(frame.data),
            DateTime.now(),
          );
          if (level != null) onLevel(level);
        },
        options: _rendererOptions,
      );
      _track = track;
    } catch (_) {
      await track?.stop();
      await track?.dispose();
      rethrow;
    }
  }

  /// Releases the microphone. Safe to call when not running, and safe to call
  /// twice — the handles are taken before anything is awaited.
  Future<void> stop() async {
    final cancelRenderer = _cancelRenderer;
    final track = _track;
    _cancelRenderer = null;
    _track = null;
    _throttle.reset();

    await cancelRenderer?.call();
    await track?.stop();
    await track?.dispose();
  }
}
