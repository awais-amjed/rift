import 'dart:ffi';
import 'dart:io';

import '../../data/enums/noise_suppression.dart';
import '../../src/rust/api/noise_filter.dart';
import '../helper_methods.dart';

/// The noise models run inside libwebrtc's processing of the microphone, on
/// Linux and Windows (`native/noise_filter` in the runner): RNNoise built into
/// the runner, and DeepFilterNet from the Rust library, loaded the first time
/// it is picked. One switch for the whole process: every capture track, the
/// mic test's included, goes through the same processing.
///
/// Where the runner has no filter — the other platforms, or a factory that
/// was not there to attach to — a model reads as [NoiseSuppression.standard].
abstract final class NoiseFilter {
  static final _native = _NativeFilter.load();

  /// The latest choice, so a model that finishes loading after the choice
  /// has moved on is not put on.
  static NoiseSuppression? _wanted;
  static bool _deepFilterReady = false;

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
}

/// The values `rift_noise_filter_set_model` takes.
abstract final class _Model {
  static const none = 0;
  static const rnnoise = 1;
  static const deepFilter = 2;
}

class _NativeFilter {
  final void Function(int) setModel;
  final void Function(Pointer<Void>, Pointer<Void>) _setDeepFilter;

  const _NativeFilter(this.setModel, this._setDeepFilter);

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
        exe.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>)
        >('rift_noise_filter_set_deep_filter'),
      );
    } catch (e) {
      HelperMethods.printDebug('Noise filter unavailable: $e');
      return null;
    }
  }
}
