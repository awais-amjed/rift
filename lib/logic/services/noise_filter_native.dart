part of 'noise_filter_ffi.dart';

/// The values `rift_noise_filter_set_model` takes.
abstract final class _Model {
  static const none = 0;
  static const rnnoise = 1;
  // 2 was DeepFilterNet.
  static const dpdfnet = 3;
}

class _NativeFilter {
  /// Whether the runner has put its filter on the microphone.
  final bool Function() available;

  final void Function(int) setModel;
  final void Function(double) setGain;

  /// `rift_noise_filter_set_dpdfnet`; null from a runner built before it.
  final void Function(Pointer<Void>, Pointer<Void>)? _setDpdfnet;

  /// `rift_noise_filter_set_rnnoise`; null from a runner built before it,
  /// which carried RNNoise's weights itself.
  final int Function(Pointer<Void>, int)? _setRnnoise;

  /// `rift_noise_filter_take_timings`; null from a runner built before it.
  final void Function(Pointer<Int64>)? _takeTimings;

  /// Null from a runner built before it exported one.
  final void Function(int)? setSilenced;

  /// The runner's RNNoise for the mic test, by address; null from a runner
  /// built before it exported them.
  final ({int create, int process, int destroy})? rnnoise;

  const _NativeFilter(
    this.available,
    this.setModel,
    this.setGain,
    this._setDpdfnet,
    this._setRnnoise,
    this._takeTimings,
    this.setSilenced,
    this.rnnoise,
  );

  bool get canDpdfnet => _setDpdfnet != null;

  /// Hands the runner DPDFNet's frame and reset functions.
  void setDpdfnet(int process, int reset) {
    final set = _setDpdfnet;
    if (set == null) throw StateError('this runner cannot take DPDFNet');
    set(Pointer.fromAddress(process), Pointer.fromAddress(reset));
  }

  /// Hands the runner RNNoise's weights, which it copies; whether they
  /// loaded. True from a runner that has its own.
  bool setRnnoise(Uint8List weights) {
    final set = _setRnnoise;
    if (set == null) return true;
    final copy = malloc<Uint8>(weights.length);
    try {
      copy.asTypedList(weights.length).setAll(0, weights);
      return set(copy.cast(), weights.length) == 1;
    } finally {
      malloc.free(copy);
    }
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
      return _NativeFilter(
        () => available() == 1,
        exe.lookupFunction<Void Function(Int32), void Function(int)>(
          'rift_noise_filter_set_model',
        ),
        exe.lookupFunction<Void Function(Float), void Function(double)>(
          'rift_noise_filter_set_gain',
        ),
        exe.providesSymbol(_setDpdfnetName)
            ? exe.lookupFunction<
                Void Function(Pointer<Void>, Pointer<Void>),
                void Function(Pointer<Void>, Pointer<Void>)
              >(_setDpdfnetName)
            : null,
        exe.providesSymbol(_setRnnoiseName)
            ? exe.lookupFunction<
                Int32 Function(Pointer<Void>, Int32),
                int Function(Pointer<Void>, int)
              >(_setRnnoiseName)
            : null,
        exe.providesSymbol(_takeTimingsName)
            ? exe.lookupFunction<
                Void Function(Pointer<Int64>),
                void Function(Pointer<Int64>)
              >(_takeTimingsName)
            : null,
        exe.providesSymbol(_setSilencedName)
            ? exe.lookupFunction<Void Function(Int32), void Function(int)>(
                _setSilencedName,
              )
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
  static const _setRnnoiseName = 'rift_noise_filter_set_rnnoise';
  static const _setSilencedName = 'rift_noise_filter_set_silenced';

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
