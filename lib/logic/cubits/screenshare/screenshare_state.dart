part of 'screenshare_cubit.dart';

/// Where this device's own screen share stands.
enum ScreenshareStatus { idle, connecting, sharing, stopping, error }

/// This device's screen share. It runs as a second LiveKit connection, which is
/// why it has a status of its own rather than a flag on [LiveKitState].
class ScreenshareState {
  final ScreenshareStatus status;
  final String? channelId;
  final ScreenShareSettings? settings;

  /// The codec the running share sends, which Auto or a fallback may have
  /// made different from the one in [settings]. A quality change sizes its
  /// bitrate for this one.
  final VideoCodec? codec;

  /// What the server allowed this share, which a quality change is held to.
  final ServerLimits limits;
  final String? error;

  const ScreenshareState({
    this.status = ScreenshareStatus.idle,
    this.channelId,
    this.settings,
    this.codec,
    this.limits = const ServerLimits(),
    this.error,
  });

  bool get isSharing => status == ScreenshareStatus.sharing;

  bool get isConnecting => status == ScreenshareStatus.connecting;

  bool get hasError => status == ScreenshareStatus.error;

  ScreenshareState copyWith({
    ScreenshareStatus? status,
    String? channelId,
    ScreenShareSettings? settings,
    VideoCodec? codec,
    ServerLimits? limits,
    String? error,
    bool clearChannelId = false,
    bool clearSettings = false,
    bool clearError = false,
  }) {
    return ScreenshareState(
      status: status ?? this.status,
      channelId: clearChannelId ? null : (channelId ?? this.channelId),
      // The codec and the server's limits belong to the share the settings
      // describe, and go with them.
      settings: clearSettings ? null : (settings ?? this.settings),
      codec: clearSettings ? null : (codec ?? this.codec),
      limits: clearSettings ? const ServerLimits() : (limits ?? this.limits),
      error: clearError ? null : (error ?? this.error),
    );
  }
}
