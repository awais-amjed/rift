import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/enums/ducking_preference.dart';
import '../../../src/rust/api/ducking.dart';
import '../../helper_methods.dart';
import '../../services/window_focus_service.dart';
import '../../services/windows_ducking.dart';

part 'ducking_state.dart';

/// Windows turning other apps down while Rift is in a call ("ducking").
///
/// Holds what Windows is set to do, read again whenever the window comes
/// back into focus — the person changes it in Windows' own Sound window,
/// then returns — and counts the ducks, so the app can say why the music
/// went quiet and how to stop it. Whether one is worth saying anything about
/// depends on the call, which `DuckingHintListener` knows. Inert off Windows.
class DuckingCubit extends Cubit<DuckingState> {
  StreamSubscription<DuckingEvent>? _events;

  /// When Windows last let other apps back up, while it still might be the
  /// call's sound reopening rather than the call ending.
  DateTime? _restoredAt;

  /// How soon a duck after an unduck is the same one carrying on. A call's
  /// sound reopens about a second into the call: a 1.5.0 report's log has
  /// Windows restoring other sounds and lowering them again 1 ms later, and
  /// counted twice that showed the person two toasts at once.
  static const reopenGap = Duration(seconds: 1);

  DuckingCubit() : super(const DuckingState()) {
    if (!WindowsDucking.supported) return;
    refresh();
    WindowFocusService.instance.focused.addListener(_onFocus);
    _events = WindowsDucking.events().listen(
      _onEvent,
      onError: (Object e) =>
          HelperMethods.printDebug('DuckingCubit: no ducking events – $e'),
    );
  }

  /// Reads Windows' choice again.
  void refresh() {
    final preference = WindowsDucking.preference();
    if (preference != null && !isClosed) {
      emit(state.copyWith(preference: preference));
    }
  }

  void _onFocus() {
    if (WindowFocusService.instance.isFocused) refresh();
  }

  void _onEvent(DuckingEvent event) {
    refresh();
    final now = DateTime.now();
    final carriesOn = event.ducked && reopened(_restoredAt, now);
    _restoredAt = event.ducked ? null : now;
    if (event.ducked && state.lowersOthers && !carriesOn) {
      emit(
        state.copyWith(
          ducks: state.ducks + 1,
          lastByRift: event.byRift,
          ducked: true,
        ),
      );
    } else {
      emit(state.copyWith(ducked: event.ducked));
    }
  }

  /// Whether a duck at [now] is the one Windows let go of at [restoredAt],
  /// back once the call's sound reopened.
  @visibleForTesting
  static bool reopened(DateTime? restoredAt, DateTime now) =>
      restoredAt != null && now.difference(restoredAt) < reopenGap;

  @override
  Future<void> close() {
    WindowFocusService.instance.focused.removeListener(_onFocus);
    _events?.cancel();
    return super.close();
  }
}
