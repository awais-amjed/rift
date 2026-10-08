part of 'soundboard_cubit.dart';

/// Whether the selected server's clip library has loaded.
enum SoundboardStatus { idle, loading, ready, error }

/// One clip somebody else just played here.
///
/// A soundboard is the only thing in a call that is **audible and
/// anonymous**. Every other noise has a face beside it — a tile lighting up,
/// a mic glyph on a roster row — and a clip had nothing, so the person who
/// wanted it to stop had no idea who to ask. That is the whole reason this
/// exists: not a log, a name.
///
/// Only the ids are held. The clip's name and the person's are looked up
/// where the chip is drawn, because both can change and neither is this
/// cubit's to cache.
class SoundboardHeard extends Equatable {
  /// Unique per press, so two airhorns from the same person a second apart
  /// are two chips with two lifetimes rather than one that cannot be told
  /// from the other.
  final String id;

  final String userId;
  final String soundId;
  final DateTime at;

  const SoundboardHeard({
    required this.id,
    required this.userId,
    required this.soundId,
    required this.at,
  });

  @override
  List<Object?> get props => [id, userId, soundId, at];
}

/// The selected server's soundboard: its clips, what this device just fired,
/// and who else just played one.
class SoundboardState extends Equatable {
  final SoundboardStatus status;

  /// Whose library this is. Held so a reply arriving after the rail has moved
  /// on is dropped instead of drawn under the wrong server's name.
  final String? serverId;

  final List<SoundboardSound> sounds;
  final String? error;

  /// Clips fired from this device recently, so the button that sent one can
  /// say it did. Ids only; the press is over by the time anybody hears it.
  final Set<String> pressed;

  /// What other people have just played, oldest first, never more than
  /// three. Never your own press: you know what you pressed, the button
  /// already flashed, and a line naming yourself with a Mute-me button
  /// beside it is nonsense.
  final List<SoundboardHeard> recent;

  const SoundboardState({
    this.status = SoundboardStatus.idle,
    this.serverId,
    this.sounds = const [],
    this.error,
    this.pressed = const {},
    this.recent = const [],
  });

  /// Whether there is anything to show a picker for.
  bool get isEmpty => sounds.isEmpty;

  SoundboardState copyWith({
    SoundboardStatus? status,
    String? serverId,
    bool clearServerId = false,
    List<SoundboardSound>? sounds,
    String? error,
    bool clearError = false,
    Set<String>? pressed,
    List<SoundboardHeard>? recent,
  }) {
    return SoundboardState(
      status: status ?? this.status,
      serverId: clearServerId ? null : (serverId ?? this.serverId),
      sounds: sounds ?? this.sounds,
      error: clearError ? null : (error ?? this.error),
      pressed: pressed ?? this.pressed,
      recent: recent ?? this.recent,
    );
  }

  @override
  List<Object?> get props => [
    status,
    serverId,
    sounds,
    error,
    SetProp(pressed),
    recent,
  ];
}
