import 'dart:ffi';
import 'dart:io';

import '../../data/enums/noise_suppression.dart';
import '../helper_methods.dart';

/// The noise models run inside libwebrtc's processing of the microphone, on
/// Linux and Windows (`native/noise_filter` in the runner). One switch for the
/// whole process: every capture track, the mic test's included, goes through
/// the same processing.
///
/// Where the runner has no filter — the other platforms, or a factory that
/// was not there to attach to — a model reads as [NoiseSuppression.standard].
abstract final class NoiseFilter {
  static final _native = _NativeFilter.load();

  /// What the settings offer here.
  static List<NoiseSuppression> get choices => [
    NoiseSuppression.off,
    NoiseSuppression.standard,
    if (_native != null) NoiseSuppression.rnnoise,
  ];

  /// Whether libwebrtc's own suppressor should run for [mode]. It is off under
  /// a model, which replaces it.
  static bool usesBuiltIn(NoiseSuppression mode) =>
      _modelFor(mode) == 0 && mode != NoiseSuppression.off;

  /// Puts [mode]'s model on the microphone, or takes it off.
  static void use(NoiseSuppression mode) => _native?.setModel(_modelFor(mode));

  /// The value `rift_noise_filter_set_model` takes for [mode].
  static int _modelFor(NoiseSuppression mode) => switch (mode) {
    NoiseSuppression.rnnoise when _native != null => 1,
    _ => 0,
  };
}

class _NativeFilter {
  final void Function(int) setModel;

  const _NativeFilter(this.setModel);

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
      );
    } catch (e) {
      HelperMethods.printDebug('Noise filter unavailable: $e');
      return null;
    }
  }
}
