part of 'ducking_cubit.dart';

/// Immutable state for [DuckingCubit].
class DuckingState extends Equatable {
  /// What Windows does to other apps during a call; null off Windows, or
  /// before it has been read.
  final DuckingPreference? preference;

  /// Whether a duck happened in the last [DuckingCubit.hintFor], while
  /// Windows was set to turn other apps down. The title bar says so then, if
  /// Rift is in a call.
  final bool hinting;

  /// Whether the duck behind [hinting] was this process's own call.
  final bool lastByRift;

  /// Whether other apps are turned down right now. Windows keeps a duck until
  /// the call's sound closes, even after the person switches it off.
  final bool ducked;

  const DuckingState({
    this.preference,
    this.hinting = false,
    this.lastByRift = false,
    this.ducked = false,
  });

  /// Whether Windows lowers or mutes other apps during calls.
  bool get lowersOthers =>
      preference != null && preference != DuckingPreference.off;

  DuckingState copyWith({
    DuckingPreference? preference,
    bool? hinting,
    bool? lastByRift,
    bool? ducked,
  }) => DuckingState(
    preference: preference ?? this.preference,
    hinting: hinting ?? this.hinting,
    lastByRift: lastByRift ?? this.lastByRift,
    ducked: ducked ?? this.ducked,
  );

  @override
  List<Object?> get props => [preference, hinting, lastByRift, ducked];
}
