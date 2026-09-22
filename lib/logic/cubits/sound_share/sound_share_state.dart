part of 'sound_share_cubit.dart';

/// Where this device's application-sound share stands.
enum SoundShareStatus { idle, connecting, sharing, stopping, error }

/// One application's sound shared into the call, as its own connection.
class SoundShareState {
  final SoundShareStatus status;

  /// The channel the share is running in, so a share left over from another
  /// call is recognisable as one.
  final String? channelId;

  /// The application being shared, as it was listed when it was picked.
  final AudioSource? source;

  final String? error;

  const SoundShareState({
    this.status = SoundShareStatus.idle,
    this.channelId,
    this.source,
    this.error,
  });

  bool get isSharing => status == SoundShareStatus.sharing;

  bool get isConnecting => status == SoundShareStatus.connecting;

  bool get hasError => status == SoundShareStatus.error;

  /// What the controls call it: the application's name if it gave one, and
  /// otherwise the plain word, never an empty label.
  String get label {
    final name = source?.appName.trim() ?? '';
    return name.isEmpty ? 'Sound' : name;
  }

  SoundShareState copyWith({
    SoundShareStatus? status,
    String? channelId,
    AudioSource? source,
    String? error,
    bool clearChannelId = false,
    bool clearSource = false,
    bool clearError = false,
  }) {
    return SoundShareState(
      status: status ?? this.status,
      channelId: clearChannelId ? null : (channelId ?? this.channelId),
      source: clearSource ? null : (source ?? this.source),
      error: clearError ? null : (error ?? this.error),
    );
  }
}
