part of 'soundboard_cubit.dart';

enum SoundboardStatus { idle, loading, ready, error }

class SoundboardState {
  final SoundboardStatus status;

  /// Whose library this is. Held so a reply arriving after the rail has moved
  /// on is dropped instead of drawn under the wrong server's name.
  final String? serverId;

  final List<SoundboardSound> sounds;
  final String? error;

  /// Clips fired from this device recently, so the button that sent one can
  /// say it did. Ids only; the press is over by the time anybody hears it.
  final Set<String> pressed;

  const SoundboardState({
    this.status = SoundboardStatus.idle,
    this.serverId,
    this.sounds = const [],
    this.error,
    this.pressed = const {},
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
  }) {
    return SoundboardState(
      status: status ?? this.status,
      serverId: clearServerId ? null : (serverId ?? this.serverId),
      sounds: sounds ?? this.sounds,
      error: clearError ? null : (error ?? this.error),
      pressed: pressed ?? this.pressed,
    );
  }
}
