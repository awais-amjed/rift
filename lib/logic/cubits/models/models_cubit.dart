import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/model_file.dart';
import '../../../data/classes/model_progress.dart';
import '../../../data/repositories/model_repository.dart';

part 'models_state.dart';

// ── Cubit ────────────────────────────────────────────────────────────────────

/// The models downloading now, or that failed to, for the title bar's chip
/// (`ModelDownloadChip`). A model that has landed drops out: there is nothing
/// left to say about it.
class ModelsCubit extends Cubit<ModelsState> {
  final ModelRepository _models;
  late final StreamSubscription<ModelProgress> _sub;

  ModelsCubit({ModelRepository? models})
    : this._(models ?? ModelRepository.instance);

  ModelsCubit._(this._models)
    : super(ModelsState.empty.afterAll(_models.unfinished)) {
    _sub = _models.progress.listen((p) => emit(state.after(p)));
  }

  /// Asks again for every model that failed, now rather than when it is next
  /// needed: the person pressed the chip.
  void retryFailed() {
    for (final file in state.failed) {
      unawaited(
        _models
            .fetch(file, retry: true)
            .then<void>(
              (_) {},
              // Shown by the chip again, through [ModelRepository.progress].
              onError: (Object _) {},
            ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
