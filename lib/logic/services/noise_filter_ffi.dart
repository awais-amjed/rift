import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../data/classes/model_file.dart';
import '../../data/classes/model_progress.dart';
import '../../data/enums/noise_filter_work.dart';
import '../../data/enums/noise_suppression.dart';
import '../../data/model_catalog.dart';
import '../../data/repositories/model_repository.dart';
import '../../src/rust/api/mic_test.dart';
import '../../src/rust/api/noise_filter.dart';
import '../helper_methods.dart';

part 'noise_filter_dpdfnet_files.dart';
part 'noise_filter_native.dart';

/// Over the helper budget and one job: switching the runner's noise models and
/// mic volume over FFI.
///
/// The noise models run inside libwebrtc's processing of the microphone, on
/// Linux and Windows (`native/noise_filter` in the runner): RNNoise in the
/// runner, and DPDFNet from the Rust library. Each one's files are downloaded
/// the first time it is picked. One switch for the whole process: every
/// capture track, the call's included, goes through the same processing. The
/// settings mic test reads the device itself, outside libwebrtc, and is
/// handed the same choice to run there ([forMicTest]).
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

  /// The model the runner has on now, a [_Model].
  static int _on = _Model.none;

  /// Rings whenever [work] or [inEffect] may have changed.
  static final _changes = StreamController<void>.broadcast(
    onListen: _watchDownloads,
    onCancel: _unwatchDownloads,
  );

  /// The downloads, for [_changes]: one starting, landing or failing moves
  /// [work] and what stands in.
  static StreamSubscription<ModelProgress>? _downloads;

  /// Each model file's last status, so a download's progress rings once as
  /// it starts rather than with every few bytes.
  static final Map<String, ModelStatus> _downloadStatus = {};

  /// Whether the runner has been handed DPDFNet.
  static bool _dpdfnetHanded = false;

  /// Whether DPDFNet is loading, its files downloading included.
  static bool _dpdfnetLoading = false;

  /// Whether DPDFNet's files are coming down, from when they are found
  /// missing until the last one lands or fails. The download repository
  /// knows each file only while it downloads, and they come one at a time.
  static bool _dpdfnetDownloading = false;

  /// Whether DPDFNet is loading from files on the device, which takes about
  /// a tenth of a second with no model on.
  static bool _dpdfnetStarting = false;

  /// What the microphone got before the latest choice, Off or Standard, kept
  /// while the new one is still finding out whether it has to download:
  /// setting the call's microphone up for a moment's guess would only set it
  /// up again.
  static NoiseSuppression _meanwhile = NoiseSuppression.standard;

  /// Listening for a model's files to land, after they failed to.
  static StreamSubscription<ModelProgress>? _awaitingFiles;

  /// Whether the runner has RNNoise's weights.
  static bool _rnnoiseLoaded = false;

  /// Whether RNNoise's weights are loading, their download included.
  static bool _rnnoiseLoading = false;

  /// RNNoise's weights being fetched and handed to the runner.
  static Future<bool>? _rnnoiseWeights;

  /// Whether the mic test has been told where the runner's RNNoise is.
  static bool _rnnoiseHanded = false;

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
    _tell();
  }

  /// Rings whenever what [work] or [inEffect] say may have changed: the
  /// runner turning up, a model going on, its files starting to download,
  /// landing or failing.
  static Stream<void> get changes => _changes.stream;

  static void _tell() => _changes.add(null);

  static void _watchDownloads() {
    _downloads = ModelRepository.instance.progress.listen((p) {
      if (_downloadStatus[p.file.localName] == p.status) return;
      _downloadStatus[p.file.localName] = p.status;
      _tell();
    });
  }

  static Future<void> _unwatchDownloads() async {
    await _downloads?.cancel();
    _downloads = null;
  }

  /// Puts [model] on the microphone.
  static void _put(_NativeFilter native, int model) {
    _on = model;
    native.setModel(model);
    _tell();
  }

  /// The runner's filter, or the one still expected.
  static _NativeFilter? get _offered => _settled ? _native : _exports;

  /// What the noise filter is busy with for the latest choice. Rings
  /// [changes] when it moves.
  static NoiseFilterWork get work {
    if (!_settled && _exports != null) return NoiseFilterWork.starting;
    final wanted = _wanted;
    if (_native == null || !_isModel(wanted)) return NoiseFilterWork.none;
    final awaited = _awaited(wanted);
    if (awaited.any((p) => p.status == ModelStatus.loading) ||
        (wanted == NoiseSuppression.dpdfnet && _dpdfnetDownloading)) {
      return NoiseFilterWork.downloadingModel;
    }
    final on =
        _on ==
        (wanted == NoiseSuppression.dpdfnet ? _Model.dpdfnet : _Model.rnnoise);
    if (awaited.isNotEmpty && !on) return NoiseFilterWork.modelUnavailable;
    if (_dpdfnetLoading && wanted == NoiseSuppression.dpdfnet) {
      return NoiseFilterWork.loadingModel;
    }
    if (_rnnoiseLoading) return NoiseFilterWork.loadingModel;
    return NoiseFilterWork.none;
  }

  /// What the microphone gets under [mode] now. A model once it is on; while
  /// its files download, or after they failed to, whatever stands in:
  /// RNNoise for DPDFNet when its weights were here already, else Standard.
  /// Nothing for the moment DPDFNet takes to load from files already here,
  /// which is too short to set the call's microphone up twice for, and what
  /// the microphone had before while that is still being found out.
  static NoiseSuppression inEffect(NoiseSuppression mode) {
    if (!_isModel(mode)) return mode;
    if (_native == null) return NoiseSuppression.standard;
    if (_on == _Model.rnnoise) return NoiseSuppression.rnnoise;
    if (_on == _Model.dpdfnet) return NoiseSuppression.dpdfnet;
    final dpdfnet = mode == NoiseSuppression.dpdfnet;
    if (_awaited(mode).isNotEmpty || (dpdfnet && _dpdfnetDownloading)) {
      return NoiseSuppression.standard;
    }
    if (dpdfnet && _dpdfnetStarting) return NoiseSuppression.off;
    return _meanwhile;
  }

  /// The files the latest choice is waiting on, for settings to show how far
  /// they have come.
  static Set<ModelFile> get awaitedFiles => {
    for (final p in _awaited(_wanted)) p.file,
  };

  static bool _isModel(NoiseSuppression? mode) =>
      mode == NoiseSuppression.rnnoise || mode == NoiseSuppression.dpdfnet;

  /// The downloads [mode] is waiting on, running or failed: its own files,
  /// and RNNoise's while they come down to stand in for DPDFNet.
  static List<ModelProgress> _awaited(NoiseSuppression? mode) {
    final files = {
      if (mode == NoiseSuppression.dpdfnet) ...ModelCatalog.dpdfnet,
      if (mode == NoiseSuppression.rnnoise ||
          (mode == NoiseSuppression.dpdfnet && _rnnoiseLoading))
        ModelCatalog.rnnoise,
    };
    if (files.isEmpty) return const [];
    return [
      for (final p in ModelRepository.instance.unfinished)
        if (files.contains(p.file)) p,
    ];
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

  /// Whether libwebrtc's own suppressor should run for [mode]: for Standard,
  /// and for a model standing in for it until it can run ([inEffect]). It is
  /// off under a model, which replaces it.
  static bool usesBuiltIn(NoiseSuppression mode) =>
      inEffect(mode) == NoiseSuppression.standard;

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

  /// Puts [mode]'s model on the microphone, or takes it off. A model's files
  /// download the first time it is put on ([_loadRnnoise],
  /// [_DpdfnetFiles.fetch]), with Standard on meanwhile, or for DPDFNet
  /// RNNoise if its weights are on the device already ([inEffect]). DPDFNet
  /// then takes about a tenth of a second to load, with no model on. If it
  /// cannot load, RNNoise stands in. Before the runner's filter is there, it
  /// waits for it ([ready]).
  static Future<void> use(NoiseSuppression mode) async {
    final before = _wanted == null ? null : inEffect(_wanted!);
    if (before == NoiseSuppression.off ||
        before == NoiseSuppression.standard) {
      _meanwhile = before!;
    }
    _wanted = mode;
    _tell();
    if (!_settled) {
      await ready;
      if (_wanted != mode) return;
    }
    final native = _native;
    if (native == null) return;
    switch (mode) {
      case NoiseSuppression.off || NoiseSuppression.standard:
        _put(native, _Model.none);
      case NoiseSuppression.rnnoise:
        await _useRnnoise(native, NoiseSuppression.rnnoise);
      case NoiseSuppression.dpdfnet:
        await _useDpdfnet(native);
    }
  }

  static Future<void> _useDpdfnet(_NativeFilter native) async {
    if (!_dpdfnetHanded) {
      _dpdfnetLoading = true;
      _tell();
      try {
        // A download can take a while, a call's whole start; the load
        // alone does not. RNNoise stands in if its weights are here, and is
        // not fetched for it; otherwise Standard does ([inEffect]).
        if (!await _DpdfnetFiles.here()) {
          final standIn = await _rnnoiseHere(native)
              ? _Model.rnnoise
              : _Model.none;
          _dpdfnetDownloading = true;
          if (_wanted == NoiseSuppression.dpdfnet) _put(native, standIn);
        }
        try {
          await _DpdfnetFiles.fetch();
        } finally {
          _dpdfnetDownloading = false;
        }
        _dpdfnetStarting = true;
        if (_wanted == NoiseSuppression.dpdfnet) _put(native, _Model.none);
        final entry = await loadDpdfnet();
        native.setDpdfnet(entry.process.toInt(), entry.reset.toInt());
        _dpdfnetHanded = true;
      } on ModelUnavailable catch (e) {
        HelperMethods.printDebug('DPDFNet unavailable: $e');
        _useOnceFetched();
      } catch (e) {
        HelperMethods.printDebug('DPDFNet unavailable: $e');
      } finally {
        _dpdfnetLoading = false;
        _dpdfnetStarting = false;
        _tell();
      }
      if (_wanted != NoiseSuppression.dpdfnet) return;
    }
    if (_dpdfnetHanded) {
      _put(native, _Model.dpdfnet);
    } else {
      await _useRnnoise(native, NoiseSuppression.dpdfnet);
    }
  }

  /// Puts RNNoise on for [mode], chosen or standing in for DPDFNet, once its
  /// weights are loaded, with Standard on while they download ([inEffect]).
  static Future<void> _useRnnoise(
    _NativeFilter native,
    NoiseSuppression mode,
  ) async {
    if (!_rnnoiseLoaded) {
      _rnnoiseLoading = true;
      _put(native, _Model.none);
      final bool loaded;
      try {
        loaded = await _loadRnnoise(native);
      } finally {
        _rnnoiseLoading = false;
        _tell();
      }
      if (!loaded) _useOnceFetched();
      if (!loaded || _wanted != mode) return;
      if (mode == NoiseSuppression.dpdfnet && _dpdfnetHanded) return;
    }
    _put(native, _Model.rnnoise);
  }

  /// Whether RNNoise can go on without a download: loaded, or its weights on
  /// the device from an earlier run, which are loaded now.
  static Future<bool> _rnnoiseHere(_NativeFilter native) async {
    if (_rnnoiseLoaded) return true;
    if (await ModelRepository.instance.present(ModelCatalog.rnnoise) == null) {
      return false;
    }
    return _loadRnnoise(native);
  }

  /// Fetches RNNoise's weights and hands them to the runner, which carries
  /// none of its own, for the call's model and the mic test's alike. Once;
  /// a failure is tried again on the next ask. True once the runner has them.
  static Future<bool> _loadRnnoise(_NativeFilter native) async {
    if (_rnnoiseLoaded) return true;
    final loading = _rnnoiseWeights ??= _loadRnnoiseOnce(native);
    final loaded = await loading;
    if (!loaded && identical(_rnnoiseWeights, loading)) _rnnoiseWeights = null;
    return loaded;
  }

  static Future<bool> _loadRnnoiseOnce(_NativeFilter native) async {
    try {
      final file = await ModelRepository.instance.fetch(ModelCatalog.rnnoise);
      if (!native.setRnnoise(await file.readAsBytes())) {
        HelperMethods.printDebug('RNNoise: the runner refused its weights');
        return false;
      }
      HelperMethods.printDebug('RNNoise loaded');
      return _rnnoiseLoaded = true;
    } catch (e) {
      HelperMethods.printDebug('RNNoise unavailable: $e');
      return false;
    }
  }

  /// After a model's files failed to download, puts the chosen model on
  /// once they land, which they do when the person presses retry in the
  /// title bar. Kept until the chosen model is on.
  static void _useOnceFetched() {
    _awaitingFiles ??= ModelRepository.instance.progress
        .where(
          (p) =>
              p.status == ModelStatus.success &&
              (p.file == ModelCatalog.rnnoise ||
                  ModelCatalog.dpdfnet.contains(p.file)),
        )
        .listen((_) async {
          final wanted = _wanted;
          if ((wanted != NoiseSuppression.rnnoise &&
                  wanted != NoiseSuppression.dpdfnet) ||
              _dpdfnetLoading ||
              _rnnoiseLoading) {
            return;
          }
          await use(wanted!);
          final on = wanted == NoiseSuppression.dpdfnet
              ? _dpdfnetHanded
              : _rnnoiseLoaded;
          if (on && _wanted == wanted) {
            await _awaitingFiles?.cancel();
            _awaitingFiles = null;
          }
        });
  }

  /// Has DPDFNet run DPDFNet-2 alone when [small], in calls and the mic test
  /// alike, or DPDFNet-8 until this computer proves too slow for it in a
  /// call.
  static void useSmallDpdfnet(bool small) {
    if (_exports == null) return;
    setDpdfnetSmall(small: small);
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
  /// how many frames it sent unfiltered, which it does with one it failed on.
  static void callEnded() {
    if (_dpdfnetHanded) {
      if (takeDpdfnetFellBack()) {
        HelperMethods.printDebug(
          'DPDFNet: too slow here for DPDFNet-8, ran DPDFNet-2',
        );
      }
      final unfiltered = takeDpdfnetUnfiltered();
      if (unfiltered > 0) {
        HelperMethods.printDebug(
          'DPDFNet: failed on $unfiltered frames, sent unfiltered',
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

  /// Has the settings mic test process the microphone as the call does now
  /// under [mode] ([inEffect]) and [autoGain], here: the test reads the
  /// device itself, so the runner's filter never sees it
  /// (`rust/src/mic_test/clean.rs`). Reaches a test already running, and is
  /// asked again whenever what the call gets moves.
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
    await setMicTestProcessing(
      noise: switch (inEffect(mode)) {
        NoiseSuppression.off => MicTestNoise.off,
        NoiseSuppression.standard => MicTestNoise.standard,
        NoiseSuppression.rnnoise => MicTestNoise.rnnoise,
        NoiseSuppression.dpdfnet => MicTestNoise.dpdfnet,
      },
      autoGain: autoGain,
    );
  }
}
