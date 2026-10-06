import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/update_repository.dart';
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
class UpdateCubit extends Cubit<UpdateState> {
  final UpdateRepository _repository;
  final AppCubit _appCubit;

  static const firstCheckAfter = Duration(seconds: 20);
  static const checkEvery = Duration(hours: 6);

  Timer? _timer;
  StreamSubscription<int>? _download;
  StreamSubscription<AppState>? _settings;
  late bool _betas = _wantsBetas;

  UpdateCubit({
    required AppCubit appCubit,
    UpdateRepository repository = const UpdateRepository(),
  }) : _appCubit = appCubit,
       _repository = repository,
       super(
         UpdateRepository.installedVersion == null
             ? const UpdateState(status: UpdateStatus.unsupported)
             : UpdateState(
                 status: UpdateStatus.upToDate,
                 installedVersion: UpdateRepository.installedVersion,
               ),
       ) {
    if (!state.canUpdate) return;
    _timer = Timer(firstCheckAfter, _scheduled);
    // Turning betas on is a reason to look again now, not in six hours.
    _settings = appCubit.stream.listen((_) {
      if (_wantsBetas == _betas) return;
      _betas = _wantsBetas;
      unawaited(check());
    });
  }

  bool get _wantsBetas =>
      _appCubit.state.wantsBetaUpdates(state.installedVersion);

  void _scheduled() {
    _timer = Timer(checkEvery, _scheduled);
    unawaited(check());
  }

  /// Looks for a newer release and, if there is one, downloads it.
  Future<void> check() async {
    if (!state.canUpdate || state.busy || isClosed) return;
    emit(state.copyWith(status: UpdateStatus.checking, clearError: true));
    try {
      final found = await _repository.check(includePrereleases: _betas);
      if (isClosed) return;
      if (found == null) {
        emit(state.copyWith(status: UpdateStatus.upToDate));
        return;
      }
      emit(
        state.copyWith(
          status: UpdateStatus.downloading,
          version: found.version,
          notes: found.notesMarkdown,
          progress: 0,
        ),
      );
      _startDownload();
    } catch (e) {
      HelperMethods.printDebug('UpdateCubit: check – $e');
      if (!isClosed) {
        emit(state.copyWith(status: UpdateStatus.failed, error: '$e'));
      }
    }
  }

  void _startDownload() {
    _download = _repository.download().listen(
      (progress) {
        if (!isClosed) emit(state.copyWith(progress: progress));
      },
      onError: (Object e) {
        HelperMethods.printDebug('UpdateCubit: download – $e');
        if (!isClosed) {
          emit(state.copyWith(status: UpdateStatus.failed, error: '$e'));
        }
      },
      onDone: () {
        if (isClosed || state.status != UpdateStatus.downloading) return;
        emit(state.copyWith(status: UpdateStatus.ready, progress: 100));
      },
    );
  }

  /// Quits Rift for the updater, which starts the new version once it is in
  /// place. Leaving a call is the caller's to confirm first: quitting leaves
  /// it, as Quit in the tray does.
  Future<void> restartToUpdate() async {
    if (state.status != UpdateStatus.ready) return;
    emit(state.copyWith(status: UpdateStatus.restarting));
    try {
      await _repository.applyOnExit();
    } catch (e) {
      HelperMethods.printDebug('UpdateCubit: apply – $e');
      if (!isClosed) {
        emit(state.copyWith(status: UpdateStatus.failed, error: '$e'));
      }
      return;
    }
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
