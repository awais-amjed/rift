part of 'ducking_cubit.dart';

/// Immutable state for [DuckingCubit].
class DuckingState extends Equatable {
  /// What Windows does to other apps during a call; null off Windows, or
  /// before it has been read.
  final DuckingPreference? preference;

  /// Counts the times Windows turned other apps down while it was set to.
  /// A listener tells the person each time it moves, if Rift is in a call.
  final int ducks;

  /// Whether the last of [ducks] was this process's own call.
  final bool lastByRift;

  /// Whether other apps are turned down right now. Windows keeps a duck until
  /// the call's sound closes, even after the person switches it off.
  final bool ducked;

  const DuckingState({
    this.preference,
    this.ducks = 0,
    this.lastByRift = false,
    this.ducked = false,
  });

  /// Whether Windows lowers or mutes other apps during calls.
  bool get lowersOthers =>
      preference != null && preference != DuckingPreference.off;

  DuckingState copyWith({
    DuckingPreference? preference,
    int? ducks,
    bool? lastByRift,
    bool? ducked,
  }) => DuckingState(
    preference: preference ?? this.preference,
    ducks: ducks ?? this.ducks,
    lastByRift: lastByRift ?? this.lastByRift,
    ducked: ducked ?? this.ducked,
  );

  @override
  List<Object?> get props => [preference, ducks, lastByRift, ducked];
}
