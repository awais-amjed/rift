import 'dart:async';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';

import '../../src/rust/api/mic_test.dart' as rust;
import 'host_platform.dart';
import 'level_throttle.dart';
import 'mic_tap_format.dart';
import 'pcm_level.dart';

/// Opens a microphone of its own and reports its level, for the mic test in
/// settings. On Windows and Linux it also plays the microphone back, so you
/// hear what Rift hears.
///
/// Deliberately the same measurement as the one running during a call — raw
/// PCM through [PcmLevel] — so the meter reads the same whether it is watching
/// its own capture or borrowing the call's. Two different units behind one bar
/// is how the threshold marker came to mean nothing.
class MicTestCapture {
  final LevelThrottle _throttle = LevelThrottle();

  LocalAudioTrack? _track;
  CancelListenFunc? _cancelRenderer;

  /// The device read directly, on Windows and Linux — see
  /// [_startReadingDevice].
  /// Cancelled in [stop], through a local taken before the first await.
  // ignore: cancel_subscriptions
  StreamSubscription<Int16List>? _samples;

  bool get isRunning => _track != null || _samples != null;

  /// Opens the microphone with [options] and calls [onLevel] as it runs,
  /// playing it on [playback] where the device is read directly
  /// ([HostPlatform.micTestReadsDevice]); elsewhere there is nothing to play
  /// it with.
  ///
  /// Throws if the device cannot be opened, having released anything it
  /// managed to acquire first.
  Future<void> start({
    required AudioCaptureOptions options,
    rust.MicTestPlayback? playback,
    required void Function(double level) onLevel,
  }) async {
    if (isRunning) return;
    _throttle.reset();
    if (HostPlatform.micTestReadsDevice) {
      return _startReadingDevice(options.deviceId, playback, onLevel);
    }

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
        options: micTapFormat,
      );
      _track = track;
    } catch (_) {
      await track?.stop();
      await track?.dispose();
      rethrow;
    }
  }

  /// Reads [deviceId] itself — `null` is the system default — rather than
  /// through a WebRTC track.
  ///
  /// WebRTC only records while a call is sending, so outside a call a track
  /// made for the test never received a sample: the meter stayed dark, and
  /// neither Windows nor PulseAudio showed the microphone being opened. The
  /// Rust side reads the device in the meter's own format ([micTapFormat]), so
  /// the same [PcmLevel] reading applies. What it cannot show is WebRTC's noise
  /// suppression and gain control, which only exist inside a call.
  ///
  /// Throws, like the WebRTC path, if the device cannot be opened: that shows
  /// as the stream's first event being an error.
  Future<void> _startReadingDevice(
    String? deviceId,
    rust.MicTestPlayback? playback,
    void Function(double level) onLevel,
  ) async {
    final opened = Completer<void>();
    _samples = rust
        .micTestSamples(deviceId: deviceId, playback: playback)
        .listen(
          (samples) {
            if (!opened.isCompleted) opened.complete();
            final level = _throttle.add(
              PcmLevel.fromInt16(
                samples.buffer.asUint8List(
                  samples.offsetInBytes,
                  samples.lengthInBytes,
                ),
              ),
              DateTime.now(),
            );
            if (level != null) onLevel(level);
          },
          onError: (Object e) {
            if (!opened.isCompleted) opened.completeError(e);
          },
        );
    try {
      // A working device delivers within a few milliseconds, silence
      // included; waiting longer than this would only hold the button up.
      await opened.future.timeout(_firstSamples, onTimeout: () {});
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  static const Duration _firstSamples = Duration(seconds: 2);

  /// Releases the microphone. Safe to call when not running, and safe to call
  /// twice — the handles are taken before anything is awaited.
  Future<void> stop() async {
    final cancelRenderer = _cancelRenderer;
    final track = _track;
    final samples = _samples;
    _cancelRenderer = null;
    _track = null;
    _samples = null;
    _throttle.reset();

    if (samples != null) {
      await samples.cancel();
      await rust.stopMicTest();
    }
    await cancelRenderer?.call();
    await track?.stop();
    await track?.dispose();
  }
}
