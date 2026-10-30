import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../data/enums/noise_filter_priority.dart';
import '../../data/enums/noise_filter_work.dart';
import '../../data/enums/noise_suppression.dart';
import '../../src/rust/api/mic_test.dart';
import '../../src/rust/api/noise_filter.dart';
import '../helper_methods.dart';

/// Over the helper budget and one job: switching the runner's noise models and
/// mic volume over FFI.
///
/// The noise models run inside libwebrtc's processing of the microphone, on
/// Linux and Windows (`native/noise_filter` in the runner): RNNoise built into
/// the runner, and DPDFNet from the Rust library, loaded the first time it is
/// picked. One switch for the whole process: every capture track, the
/// call's capture track goes through the same processing. The settings mic
/// test reads the device itself, outside libwebrtc, and is handed the same
/// choice to run there ([forMicTest]).
///
/// The mic volume runs there too, after the model ([MicVolume]).
///
/// Where the runner has no filter — the other platforms, or a factory that
/// was not there to attach to — a model reads as [NoiseSuppression.standard].
abstract final class NoiseFilter {
  /// The runner's functions, found at once. They exist before the filter
  /// does: Windows runs Dart on its own thread, which starts before the
  /// window's thread puts the filter on (`FlutterWindow::OnCreate`).
  static final _exports = _NativeFilter.load();

  /// The runner's filter, once it says it has one ([ready]).
  static _NativeFilter? _native;

  /// Whether the wait for the runner is over, either way.
  static bool _settled = false;

  /// Completes once the runner has put its filter on, or [_runnerWait] has
  /// passed without it. Until then, what is chosen is kept and put on then.
  static final Future<void> ready = _waitForRunner();

  /// Far longer than the runner takes; a filter not there by then never
  /// will be (no factory to attach to).
  static const _runnerWait = Duration(seconds: 3);

  /// The latest choice, so a model that finishes loading after the choice
  /// has moved on is not put on.
  static NoiseSuppression? _wanted;

  /// The latest mic volume, put on when the filter arrives.
  static double? _gain;

  /// Whether the runner has been handed DPDFNet.
  static bool _dpdfnetHanded = false;

  /// Whether DPDFNet is loading.
  static bool _dpdfnetLoading = false;

  /// Whether the mic test has been told where the runner's RNNoise is.
  static bool _rnnoiseHanded = false;

  /// The beta options as last set ([usePriority], [usePreciseTiming]), and
  /// whether a call is on, which the precise timer is held for.
  static NoiseFilterPriority _priority = NoiseFilterPriority.normal;
  static bool _precise = false;
  static bool _inCall = false;

  static Future<void> _waitForRunner() async {
    final exports = _exports;
    if (exports != null) {
      // A plain read of a flag the runner sets, every few milliseconds
      // while Dart's own start-up goes on; nothing here blocks.
      final waited = Stopwatch()..start();
      while (!exports.available()) {
        if (waited.elapsed > _runnerWait) {
          HelperMethods.printDebug('Noise filter: the runner has none');
          _settled = true;
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _native = exports;
      final gain = _gain;
      if (gain != null) setGain(gain);
    }
    _settled = true;
  }

  /// The runner's filter, or the one still expected.
  static _NativeFilter? get _offered => _settled ? _native : _exports;

  /// What the noise filter is busy with, read straight after [use].
  static NoiseFilterWork get work {
    if (!_settled && _exports != null) return NoiseFilterWork.starting;
    if (_dpdfnetLoading && _wanted == NoiseSuppression.dpdfnet) {
      return NoiseFilterWork.loadingModel;
    }
    return NoiseFilterWork.none;
  }

  /// What the settings offer here. While the runner's filter is still on its
  /// way, what it will have.
  static List<NoiseSuppression> get choices => [
    NoiseSuppression.off,
    NoiseSuppression.standard,
    if (_offered != null) ...[
      NoiseSuppression.rnnoise,
      if (_offered?.canDpdfnet ?? false) NoiseSuppression.dpdfnet,
    ],
  ];

  /// Whether libwebrtc's own suppressor should run for [mode]. It is off under
  /// a model, which replaces it.
  static bool usesBuiltIn(NoiseSuppression mode) => switch (mode) {
    NoiseSuppression.off => false,
    NoiseSuppression.standard => true,
    NoiseSuppression.rnnoise || NoiseSuppression.dpdfnet => _native == null,
  };

  /// Whether the runner can turn the microphone up or down: [setGain].
  static bool get canSetGain => _offered != null;

  /// The mic volume as a gain, on every capture track and on the mic test,
  /// which reads the device itself and so does not pass the runner's filter.
  static void setGain(double gain) {
    _gain = gain;
    final native = _native;
    if (native == null) return;
    native.setGain(gain);
    unawaited(
      setMicTestGain(
        gain: gain,
      ).catchError((Object e) => HelperMethods.printDebug('Mic test gain: $e')),
    );
  }

  /// Whether the runner can send silence while the microphone keeps running:
  /// [setSilenced]. False on a runner built before it could.
  static bool get canSilence => _native?.setSilenced != null;

  /// Push-to-talk with the key up: everything the microphone hears goes out
  /// as silence from the next 10 ms, while the device keeps running.
  static void setSilenced(bool silenced) =>
      _native?.setSilenced?.call(silenced ? 1 : 0);

  /// Puts [mode]'s model on the microphone, or takes it off. DPDFNet loads
  /// first, about a tenth of a second, with no model on meanwhile; if it
  /// cannot load, RNNoise stands in. Before the runner's filter is there, it
  /// waits for it ([ready]).
  static Future<void> use(NoiseSuppression mode) async {
    _wanted = mode;
    if (!_settled) {
      await ready;
      if (_wanted != mode) return;
    }
    final native = _native;
    if (native == null) return;
    switch (mode) {
      case NoiseSuppression.off || NoiseSuppression.standard:
        native.setModel(_Model.none);
      case NoiseSuppression.rnnoise:
        native.setModel(_Model.rnnoise);
      case NoiseSuppression.dpdfnet:
        await _useDpdfnet(native);
    }
  }

  static Future<void> _useDpdfnet(_NativeFilter native) async {
    if (!_dpdfnetHanded) {
      native.setModel(_Model.none);
      _dpdfnetLoading = true;
      try {
        final entry = await loadDpdfnet();
        native.setDpdfnet(entry.process.toInt(), entry.reset.toInt());
        _dpdfnetHanded = true;
      } catch (e) {
        HelperMethods.printDebug('DPDFNet unavailable: $e');
      } finally {
        _dpdfnetLoading = false;
      }
      if (_wanted != NoiseSuppression.dpdfnet) return;
    }
    native.setModel(_dpdfnetHanded ? _Model.dpdfnet : _Model.rnnoise);
  }

  /// Has DPDFNet run DPDFNet-2 alone when [small], in calls and the mic test
  /// alike, or DPDFNet-8 until this computer proves too slow for it in a
  /// call.
  static void useSmallDpdfnet(bool small) {
    if (_exports == null) return;
    setDpdfnetSmall(small: small);
  }

  /// Where DPDFNet runs in a call, from its next frame, mid-call too: a beta
  /// option for comparing by ear. Each change mid-call goes in the log, so
  /// a bug report says which one the person was hearing when.
  static void usePriority(NoiseFilterPriority priority) {
    if (_exports == null) return;
    if (_inCall && priority != _priority) {
      HelperMethods.printDebug('DPDFNet: placed at ${priority.label}');
    }
    _priority = priority;
    setDpdfnetPlacement(
      placement: switch (priority) {
        NoiseFilterPriority.timeCritical => NoiseModelPlacement.captureThread,
        NoiseFilterPriority.highest => NoiseModelPlacement.highest,
        NoiseFilterPriority.aboveNormal => NoiseModelPlacement.aboveNormal,
        NoiseFilterPriority.normal => NoiseModelPlacement.normal,
      },
    );
  }

  /// Whether calls hold Windows' 1 ms timer, which a call already on takes
  /// or lets go of at once. A beta option, like [usePriority].
  static void usePreciseTiming(bool precise) {
    if (_exports == null) return;
    if (_inCall && precise != _precise) {
      HelperMethods.printDebug(
        'DPDFNet: precise timing ${precise ? 'on' : 'off'}',
      );
    }
    _precise = precise;
    holdPreciseTimingForCall(hold: precise && _inCall);
  }

  /// For the start of a call: holds the precise timer if asked for, and
  /// logs the beta options the call starts with.
  static void callStarted() {
    if (_exports == null) return;
    _inCall = true;
    holdPreciseTimingForCall(hold: _precise);
    if (_dpdfnetHanded) {
      HelperMethods.printDebug(
        'DPDFNet: placed at ${_priority.label}'
        '${Platform.isWindows ? ', precise timing ${_precise ? 'on' : 'off'}' : ''}',
      );
    }
  }

  /// For the end of a call. Writes how long the model took over each 10 ms
  /// of the call just ended to the app's log, as one line of numbers, and
  /// starts counting again. The
  /// runner counts on libwebrtc's capture thread and never logs from there,
  /// so this is how a machine too slow for a model shows itself. Nothing when
  /// no model ran, or from a runner built before it counted.
  ///
  /// Also says when DPDFNet went over to its small model, which it does by
  /// itself on a computer too slow for the large one, and has the next call
  /// start on the large one again: the computer may only have been busy. And
  /// how many frames it sent unfiltered, which it does with one it is late
  /// with rather than hold up the computer's other work.
  static void callEnded() {
    if (_inCall) {
      _inCall = false;
      holdPreciseTimingForCall(hold: false);
    }
    if (_dpdfnetHanded) {
      if (takeDpdfnetFellBack()) {
        HelperMethods.printDebug(
          'DPDFNet: too slow here for DPDFNet-8, ran DPDFNet-2',
        );
      }
      final unfiltered = takeDpdfnetUnfiltered();
      if (unfiltered > 0) {
        HelperMethods.printDebug(
          'DPDFNet: $unfiltered frames late, sent unfiltered',
        );
      }
      retryLargeDpdfnet();
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
    await ready;
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
