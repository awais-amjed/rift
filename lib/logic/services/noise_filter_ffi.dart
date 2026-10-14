import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../data/enums/noise_suppression.dart';
import '../../src/rust/api/mic_test.dart';
import '../../src/rust/api/noise_filter.dart';
import '../helper_methods.dart';

/// The noise models run inside libwebrtc's processing of the microphone, on
/// Linux and Windows (`native/noise_filter` in the runner): RNNoise built into
/// the runner, and DeepFilterNet and DPDFNet from the Rust library, each
/// loaded the first time it is picked. One switch for the whole process: every capture track, the
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

  /// The Rust library's models the runner has been handed.
  static final _loaded = <NoiseSuppression>{};

  /// Whether the mic test has been told where the runner's RNNoise is.
  static bool _rnnoiseHanded = false;

  /// What the settings offer here.
  static List<NoiseSuppression> get choices => [
    NoiseSuppression.off,
    NoiseSuppression.standard,
    if (_native != null) ...[
      NoiseSuppression.rnnoise,
      NoiseSuppression.deepFilter,
      if (_native?.canDpdfnet ?? false) NoiseSuppression.dpdfnet,
    ],
  ];

  /// Whether libwebrtc's own suppressor should run for [mode]. It is off under
  /// a model, which replaces it.
  static bool usesBuiltIn(NoiseSuppression mode) => switch (mode) {
    NoiseSuppression.off => false,
    NoiseSuppression.standard => true,
    NoiseSuppression.rnnoise ||
    NoiseSuppression.deepFilter ||
    NoiseSuppression.dpdfnet => _native == null,
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
  /// and DPDFNet load first, a tenth to a quarter of a second, with no model
  /// on meanwhile; if one cannot load, RNNoise stands in.
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
        await _useLibraryModel(native, mode, _Model.deepFilter);
      case NoiseSuppression.dpdfnet:
        await _useLibraryModel(native, mode, _Model.dpdfnet);
    }
  }

  static Future<void> _useLibraryModel(
    _NativeFilter native,
    NoiseSuppression mode,
    int model,
  ) async {
    if (!_loaded.contains(mode)) {
      native.setModel(_Model.none);
      try {
        final entry = mode == NoiseSuppression.dpdfnet
            ? await loadDpdfnet()
            : await loadDeepFilter();
        native.setLibraryModel(
          model,
          entry.process.toInt(),
          entry.reset.toInt(),
        );
        _loaded.add(mode);
      } catch (e) {
        HelperMethods.printDebug('${mode.label} unavailable: $e');
      }
      if (_wanted != mode) return;
    }
    native.setModel(_loaded.contains(mode) ? model : _Model.rnnoise);
  }

  /// Writes how long the model took over each 10 ms of the call just ended
  /// to the app's log, as one line of numbers, and starts counting again. The
  /// runner counts on libwebrtc's capture thread and never logs from there,
  /// so this is how a machine too slow for a model shows itself. Nothing when
  /// no model ran, or from a runner built before it counted.
  ///
  /// Also says when DPDFNet went over to its small model, which it does by
  /// itself on a computer too slow for the large one.
  static void logTimings() {
    if (_loaded.contains(NoiseSuppression.dpdfnet) && takeDpdfnetFellBack()) {
      HelperMethods.printDebug(
        'DPDFNet: too slow here for DPDFNet-8, running DPDFNet-2',
      );
    }
    final timings = _native?.takeTimings();
    if (timings == null || timings.frames == 0) return;
    final worst = (timings.worstMicros / 1000).toStringAsFixed(1);
    HelperMethods.printDebug(
      'Noise filter: ${timings.frames} frames, worst $worst ms, '
      '${timings.over5ms} over 5 ms, ${timings.over10ms} over 10 ms',
    );
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
        NoiseSuppression.dpdfnet =>
          hasModels ? MicTestNoise.dpdfnet : MicTestNoise.standard,
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
  static const dpdfnet = 3;
}

class _NativeFilter {
  final void Function(int) setModel;
  final void Function(double) setGain;
  final void Function(Pointer<Void>, Pointer<Void>) _setDeepFilter;

  /// `rift_noise_filter_set_dpdfnet`; null from a runner built before it.
  final void Function(Pointer<Void>, Pointer<Void>)? _setDpdfnet;

  /// `rift_noise_filter_take_timings`; null from a runner built before it.
  final void Function(Pointer<Int64>)? _takeTimings;

  /// The runner's RNNoise for the mic test, by address; null from a runner
  /// built before it exported them.
  final ({int create, int process, int destroy})? rnnoise;

  const _NativeFilter(
    this.setModel,
    this.setGain,
    this._setDeepFilter,
    this._setDpdfnet,
    this._takeTimings,
    this.rnnoise,
  );

  bool get canDpdfnet => _setDpdfnet != null;

  /// Hands the runner the Rust library's [model] (a [_Model] value).
  void setLibraryModel(int model, int process, int reset) {
    final set = model == _Model.dpdfnet ? _setDpdfnet : _setDeepFilter;
    if (set == null) throw StateError('this runner cannot take DPDFNet');
    set(Pointer.fromAddress(process), Pointer.fromAddress(reset));
  }

  ({int frames, int over5ms, int over10ms, int worstMicros})? takeTimings() {
    final take = _takeTimings;
    if (take == null) return null;
    final out = calloc<Int64>(4);
    try {
      take(out);
      return (
        frames: out[0],
        over5ms: out[1],
        over10ms: out[2],
        worstMicros: out[3],
      );
    } finally {
      calloc.free(out);
    }
  }

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
        exe.providesSymbol(_setDpdfnetName)
            ? exe.lookupFunction<
                Void Function(Pointer<Void>, Pointer<Void>),
                void Function(Pointer<Void>, Pointer<Void>)
              >(_setDpdfnetName)
            : null,
        exe.providesSymbol(_takeTimingsName)
            ? exe.lookupFunction<
                Void Function(Pointer<Int64>),
                void Function(Pointer<Int64>)
              >(_takeTimingsName)
            : null,
        _rnnoiseIn(exe),
      );
    } catch (e) {
      HelperMethods.printDebug('Noise filter unavailable: $e');
      return null;
    }
  }

  static const _takeTimingsName = 'rift_noise_filter_take_timings';
  static const _setDpdfnetName = 'rift_noise_filter_set_dpdfnet';

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
