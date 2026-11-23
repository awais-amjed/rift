import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/call_to_resume.dart';
import '../../../data/repositories/update_repository.dart';
import '../../../src/rust/api/updater.dart' show UpdateDownloadProgress;
import '../../helper_methods.dart';
import '../../services/tray_service/tray_service.dart';
import '../app/app_cubit.dart';

part 'update_state.dart';

/// Whether a newer Rift is out, and getting it ready.
///
/// Looks shortly after start and every [checkEvery] after that, downloads
/// what it finds straight away, and then waits: nothing restarts Rift but the
/// person, from the title bar or Settings. An update left waiting is put in
/// place at the next start anyway (see [UpdateRepository.startup]).
///
/// A check the person makes ([checkNow]) only finds: the download waits for
/// them to ask ([download]). Either download can be paused, resumed and
/// cancelled, and a cancelled version is not fetched again by the timer —
/// it stays there for the person to download.
class UpdateCubit extends Cubit<UpdateState> {
  final UpdateRepository _repository;
  final AppCubit _appCubit;

  static const firstCheckAfter = Duration(seconds: 20);
  static const checkEvery = Duration(hours: 6);

  /// When to look again after a check or download failed, rather than
  /// [checkEvery]: most failures are a network that was away for a moment.
  static const retryAfter = Duration(minutes: 30);

  Timer? _timer;
  StreamSubscription<UpdateDownloadProgress>? _download;
  StreamSubscription<AppState>? _settings;

  /// Whether checks take betas, as last seen in settings. Set in the
  /// constructor, not on first read: the settings listener reads it first,
  /// and would take the change it is there to notice as the starting value.
  late bool _betas;

  /// The version whose download the person cancelled.
  String? _cancelled;

  UpdateCubit({
    required AppCubit appCubit,
    UpdateRepository repository = const UpdateRepository(),
  }) : _appCubit = appCubit,
       _repository = repository,
       super(
         repository.installed == null
             ? const UpdateState(status: UpdateStatus.unsupported)
             : UpdateState(
                 status: UpdateStatus.upToDate,
                 installedVersion: repository.installed,
               ),
       ) {
    if (!state.canUpdate) return;
    // A beta's unset choice follows the version, so the stable it updates to
    // would turn betas off by itself. Saving it now keeps them on.
    if (appCubit.state.betaUpdates == null &&
        (state.installedVersion?.contains('-') ?? false)) {
      appCubit.setBetaUpdates(true);
    }
    _betas = _wantsBetas;
    _timer = Timer(firstCheckAfter, _scheduled);
    _settings = appCubit.stream.listen((_) {
      if (_wantsBetas == _betas) return;
      _betas = _wantsBetas;
      unawaited(_betasChanged());
    });
  }

  /// Turning betas on is a reason to look again now, not in six hours. The
  /// person is in Settings, so what it finds waits for them. Turning them
  /// off also stops a beta on its way, and throws away one waiting for a
  /// restart, which the next start would otherwise put in place.
  Future<void> _betasChanged() async {
    if (_unwanted(state.version)) {
      switch (state.status) {
        case UpdateStatus.downloading || UpdateStatus.paused
            when !state.preparing:
          _stopDownload();
        case UpdateStatus.ready:
          await _discard();
        default:
      }
    }
    // A check under way looks again itself once it ends (see [_check]).
    await checkNow();
  }

  /// Whether [version] is a beta while betas are off.
  bool _unwanted(String? version) =>
      !_betas && (version?.contains('-') ?? false);

  /// Throws away the downloaded update, which is no longer wanted.
  Future<void> _discard() async {
    try {
      await _repository.discardPending();
    } catch (e) {
      HelperMethods.printDebug('UpdateCubit: discard – $e');
    }
    if (!isClosed) emit(state.copyWith(status: UpdateStatus.upToDate));
  }

  /// Looks again in [retryAfter] rather than [checkEvery].
  void _retrySoon() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = Timer(retryAfter, _scheduled);
  }

  bool get _wantsBetas =>
      _appCubit.state.wantsBetaUpdates(state.installedVersion);

  void _scheduled() {
    _timer = Timer(checkEvery, _scheduled);
    unawaited(checkInBackground());
  }

  /// Looks for a newer release because the person asked: what it finds
  /// waits for [download]. It stands in for the timer's next check too, or a
  /// check due a moment later (the first, [firstCheckAfter] from start)
  /// would download what the person was only shown.
  Future<void> checkNow() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = Timer(checkEvery, _scheduled);
    }
    return _check(fetch: false);
  }

  /// The timer's check, which downloads what it finds straight away — unless
  /// it is the version the person cancelled.
  Future<void> checkInBackground() => _check(fetch: true);

  Future<void> _check({required bool fetch}) async {
    if (!state.canUpdate || state.busy || isClosed) return;
    emit(state.copyWith(status: UpdateStatus.checking, clearError: true));
    final betas = _betas;
    try {
      final found = await _repository.check(includePrereleases: betas);
      if (isClosed) return;
      if (betas != _betas) {
        // Betas were turned on or off while it looked: what it found is
        // for the old choice.
        emit(state.copyWith(status: UpdateStatus.upToDate));
        await _check(fetch: fetch);
        return;
      }
      if (found == null) {
        emit(state.copyWith(status: UpdateStatus.upToDate));
        return;
      }
      emit(
        state.copyWith(
          status: UpdateStatus.available,
          version: found.version,
          notes: found.notesMarkdown,
          totalBytes: found.downloadBytes,
          downloadedBytes: 0,
          bytesPerSecond: 0,
        ),
      );
      if (fetch && found.version != _cancelled) download();
    } catch (e) {
      HelperMethods.printDebug('UpdateCubit: check – $e');
      if (!isClosed) {
        emit(
          state.copyWith(
            status: UpdateStatus.failed,
            error: '$e',
            failure: UpdateFailure.check,
          ),
        );
        _retrySoon();
      }
    }
  }

  /// Downloads the update the last check found.
  void download() {
    if (state.status != UpdateStatus.available || isClosed) return;
    emit(
      state.copyWith(
        status: UpdateStatus.downloading,
        downloadedBytes: 0,
        bytesPerSecond: 0,
      ),
    );
    _download = _repository.download().listen(
      (progress) {
        if (isClosed) return;
        emit(
          state.copyWith(
            downloadedBytes: progress.downloadedBytes,
            totalBytes: progress.totalBytes > 0 ? progress.totalBytes : null,
            bytesPerSecond: state.status == UpdateStatus.paused
                ? 0
                : progress.bytesPerSecond,
          ),
        );
      },
      onError: (Object e) {
        HelperMethods.printDebug('UpdateCubit: download – $e');
        _download = null;
        if (!isClosed) {
          emit(
            state.copyWith(
              status: UpdateStatus.failed,
              error: '$e',
              failure: UpdateFailure.download,
            ),
          );
          _retrySoon();
        }
      },
      onDone: () {
        _download = null;
        // Paused too: a pause pressed just as the last bytes came in lands
        // after the download has ended, and the update is ready all the same.
        final going =
            state.status == UpdateStatus.downloading ||
            state.status == UpdateStatus.paused;
        if (isClosed || !going) return;
        if (_unwanted(state.version)) {
          // Betas were turned off while it was being put together.
          unawaited(_discard().then((_) => checkNow()));
          return;
        }
        emit(
          state.copyWith(
            status: UpdateStatus.ready,
            downloadedBytes: state.totalBytes,
            bytesPerSecond: 0,
          ),
        );
      },
    );
  }

  /// Holds the download where it is; [resume] carries it on.
  void pause() {
    if (state.status != UpdateStatus.downloading || state.preparing) return;
    emit(state.copyWith(status: UpdateStatus.paused, bytesPerSecond: 0));
    unawaited(_repository.pause());
  }

  void resume() {
    if (state.status != UpdateStatus.paused) return;
    emit(state.copyWith(status: UpdateStatus.downloading));
    unawaited(_repository.resume());
  }

  /// Ends the download and throws away what it brought. The update stays
  /// found, for the person to download after all.
  void cancel() {
    final going =
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.paused;
    if (!going || state.preparing) return;
    _cancelled = state.version;
    _stopDownload();
  }

  /// Ends the download; the update it was for stays found.
  void _stopDownload() {
    unawaited(_download?.cancel());
    _download = null;
    emit(
      state.copyWith(
        status: UpdateStatus.available,
        downloadedBytes: 0,
        bytesPerSecond: 0,
      ),
    );
    unawaited(_repository.cancel());
  }

  /// Quits Rift for the updater, which starts the new version once it is in
  /// place. Quitting leaves a call, as Quit in the tray does; [call] is the
  /// one to rejoin when the new version starts.
  Future<void> restartToUpdate({CallToResume? call}) async {
    if (state.status != UpdateStatus.ready) return;
    emit(state.copyWith(status: UpdateStatus.restarting));
    try {
      await _repository.applyOnExit();
    } catch (e) {
      HelperMethods.printDebug('UpdateCubit: apply – $e');
      if (!isClosed) {
        emit(
          state.copyWith(
            status: UpdateStatus.failed,
            error: '$e',
            failure: UpdateFailure.apply,
          ),
        );
      }
      return;
    }
    // Only once the update is sure to run: a failed apply keeps Rift open,
    // and the call with it.
    if (call != null) _appCubit.rememberCallToResume(call);
    await TrayService.instance.quit();
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _download?.cancel();
    _settings?.cancel();
    return super.close();
  }
}
