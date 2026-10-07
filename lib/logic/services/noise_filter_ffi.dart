import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import '../../data/enums/noise_suppression.dart';
import '../../src/rust/api/mic_test.dart';
import '../../src/rust/api/noise_filter.dart';
import '../helper_methods.dart';

/// The noise models run inside libwebrtc's processing of the microphone, on
/// Linux and Windows (`native/noise_filter` in the runner): RNNoise built into
/// the runner, and DeepFilterNet from the Rust library, loaded the first time
/// it is picked. One switch for the whole process: every capture track, the
/// call's capture track goes through the same processing. The settings mic
/// test reads the device itself, outside libwebrtc, and is handed the same
/// choice to run there ([forMicTest]).
///
/// The mic volume runs there too, after the model ([MicVolume]).
///
/// Where the runner has no filter — the other platforms, or a factory that
/// was not there to attach to — a model reads as [NoiseSuppression.standard].
abstract final class NoiseFilter {
  static final _native = _NativeFilter.load();

  /// The latest choice, so a model that finishes loading after the choice
  /// has moved on is not put on.
  static NoiseSuppression? _wanted;
  static bool _deepFilterReady = false;

  /// Whether the mic test has been told where the runner's RNNoise is.
  static bool _rnnoiseHanded = false;

  /// What the settings offer here.
  static List<NoiseSuppression> get choices => [
    NoiseSuppression.off,
    NoiseSuppression.standard,
    if (_native != null) ...[
      NoiseSuppression.rnnoise,
      NoiseSuppression.deepFilter,
    ],
  ];

  /// Whether libwebrtc's own suppressor should run for [mode]. It is off under
  /// a model, which replaces it.
  static bool usesBuiltIn(NoiseSuppression mode) => switch (mode) {
    NoiseSuppression.off => false,
    NoiseSuppression.standard => true,
    NoiseSuppression.rnnoise || NoiseSuppression.deepFilter => _native == null,
  };

  /// Whether the runner can turn the microphone up or down: [setGain].
  static bool get canSetGain => _native != null;

  /// The mic volume as a gain, on every capture track and on the mic test,
  /// which reads the device itself and so does not pass the runner's filter.
  static void setGain(double gain) {
    final native = _native;
    if (native == null) return;
    native.setGain(gain);
    unawaited(
      setMicTestGain(
        gain: gain,
      ).catchError((Object e) => HelperMethods.printDebug('Mic test gain: $e')),
    );
  }

  /// Puts [mode]'s model on the microphone, or takes it off. DeepFilterNet
  /// loads first, about a quarter of a second, with no model on meanwhile;
  /// if it cannot load, RNNoise stands in.
  static Future<void> use(NoiseSuppression mode) async {
    final native = _native;
    if (native == null) return;
    _wanted = mode;
    switch (mode) {
      case NoiseSuppression.off || NoiseSuppression.standard:
        native.setModel(_Model.none);
      case NoiseSuppression.rnnoise:
        native.setModel(_Model.rnnoise);
      case NoiseSuppression.deepFilter:
        if (!_deepFilterReady) {
          native.setModel(_Model.none);
          try {
            final entry = await loadDeepFilter();
            native.setDeepFilter(entry.process.toInt(), entry.reset.toInt());
            _deepFilterReady = true;
          } catch (e) {
            HelperMethods.printDebug('DeepFilterNet unavailable: $e');
          }
          if (_wanted != NoiseSuppression.deepFilter) return;
        }
        native.setModel(_deepFilterReady ? _Model.deepFilter : _Model.rnnoise);
    }
  }

  /// Has the settings mic test process the microphone as a call would under
  /// [mode] and [autoGain], here: the test reads the device itself, so the
  /// runner's filter never sees it (`rust/src/mic_test/clean.rs`). Reaches a
  /// test already running.
  static Future<void> forMicTest(
    NoiseSuppression mode, {
    required bool autoGain,
  }) async {
    final native = _native;
    if (native != null && !_rnnoiseHanded) {
      final rnnoise = native.rnnoise;
      if (rnnoise != null) {
        await setMicTestRnnoise(
          create: BigInt.from(rnnoise.create),
          process: BigInt.from(rnnoise.process),
          destroy: BigInt.from(rnnoise.destroy),
        );
      }
      _rnnoiseHanded = true;
    }
    final hasModels = native?.rnnoise != null;
    await setMicTestProcessing(
      noise: switch (mode) {
        NoiseSuppression.off => MicTestNoise.off,
        NoiseSuppression.standard => MicTestNoise.standard,
        // Where the runner has no models the call falls back to the built-in
        // suppressor, and so does the test.
        NoiseSuppression.rnnoise =>
          hasModels ? MicTestNoise.rnnoise : MicTestNoise.standard,
        NoiseSuppression.deepFilter =>
          hasModels ? MicTestNoise.deepFilter : MicTestNoise.standard,
      },
      autoGain: autoGain,
    );
  }
}

/// The values `rift_noise_filter_set_model` takes.
abstract final class _Model {
  static const none = 0;
  static const rnnoise = 1;
  static const deepFilter = 2;
}

class _NativeFilter {
  final void Function(int) setModel;
  final void Function(double) setGain;
  final void Function(Pointer<Void>, Pointer<Void>) _setDeepFilter;

  /// The runner's RNNoise for the mic test, by address; null from a runner
  /// built before it exported them.
  final ({int create, int process, int destroy})? rnnoise;

  const _NativeFilter(
    this.setModel,
    this.setGain,
    this._setDeepFilter,
    this.rnnoise,
  );

  void setDeepFilter(int process, int reset) =>
      _setDeepFilter(Pointer.fromAddress(process), Pointer.fromAddress(reset));

  static _NativeFilter? load() {
    if (!Platform.isLinux && !Platform.isWindows) return null;
    try {
      final exe = DynamicLibrary.executable();
      if (!exe.providesSymbol('rift_noise_filter_available')) return null;
      final available = exe.lookupFunction<Int32 Function(), int Function()>(
        'rift_noise_filter_available',
      );
      if (available() != 1) return null;
      return _NativeFilter(
        exe.lookupFunction<Void Function(Int32), void Function(int)>(
          'rift_noise_filter_set_model',
        ),
        exe.lookupFunction<Void Function(Float), void Function(double)>(
          'rift_noise_filter_set_gain',
        ),
        exe.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>)
        >('rift_noise_filter_set_deep_filter'),
        _rnnoiseIn(exe),
      );
    } catch (e) {
      HelperMethods.printDebug('Noise filter unavailable: $e');
      return null;
    }
  }

  static ({int create, int process, int destroy})? _rnnoiseIn(
    DynamicLibrary exe,
  ) {
    const names = (
      create: 'rift_noise_filter_rnnoise_create',
      process: 'rift_noise_filter_rnnoise_process',
      destroy: 'rift_noise_filter_rnnoise_destroy',
    );
    if (![
      names.create,
      names.process,
      names.destroy,
    ].every(exe.providesSymbol)) {
      return null;
    }
    return (
      create: exe.lookup<Void>(names.create).address,
      process: exe.lookup<Void>(names.process).address,
      destroy: exe.lookup<Void>(names.destroy).address,
    );
  }
}
