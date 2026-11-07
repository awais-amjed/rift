part of 'screenshare_cubit.dart';

/// Where this device's own screen share stands.
enum ScreenshareStatus { idle, connecting, sharing, stopping, error }

/// This device's screen share. It runs as a second LiveKit connection, which is
/// why it has a status of its own rather than a flag on [LiveKitState].
class ScreenshareState extends Equatable {
  final ScreenshareStatus status;
  final String? channelId;
  final ScreenShareSettings? settings;

  /// The codec the running share sends, which Auto or a fallback may have
  /// made different from the one in [settings]. A quality change sizes its
  /// bitrate for this one.
  final VideoCodec? codec;

  /// The best the running share may send: what was picked or Auto chose, or
  /// less once the GPU has failed. Watchers may hold [codec] below it
  /// (`ShareLadder`).
  final VideoCodec? topCodec;

  /// What the server allowed this share, which a quality change is held to.
  final ServerLimits limits;
  final String? error;

  /// The last thing to tell the person, shown once by `NoticeListeners`.
  final Notice? notice;

  const ScreenshareState({
    this.status = ScreenshareStatus.idle,
    this.channelId,
    this.settings,
    this.codec,
    this.topCodec,
    this.limits = const ServerLimits(),
    this.error,
    this.notice,
  });

  bool get isSharing => status == ScreenshareStatus.sharing;

  bool get isConnecting => status == ScreenshareStatus.connecting;

  bool get hasError => status == ScreenshareStatus.error;

  /// Whether nothing is starting, running or stopping, so a new share may
  /// start. Rust holds one share at a time.
  bool get canStart => status == ScreenshareStatus.idle || hasError;

  ScreenshareState copyWith({
    ScreenshareStatus? status,
    String? channelId,
    ScreenShareSettings? settings,
    VideoCodec? codec,
    VideoCodec? topCodec,
    ServerLimits? limits,
    String? error,
    bool clearChannelId = false,
    bool clearSettings = false,
    bool clearError = false,
    Notice? notice,
  }) {
    return ScreenshareState(
      status: status ?? this.status,
      channelId: clearChannelId ? null : (channelId ?? this.channelId),
      // The codec and the server's limits belong to the share the settings
      // describe, and go with them.
      settings: clearSettings ? null : (settings ?? this.settings),
      codec: clearSettings ? null : (codec ?? this.codec),
      topCodec: clearSettings ? null : (topCodec ?? this.topCodec),
      limits: clearSettings ? const ServerLimits() : (limits ?? this.limits),
      error: clearError ? null : (error ?? this.error),
      notice: notice ?? this.notice,
    );
  }

  @override
  List<Object?> get props => [
    status,
    channelId,
    settings,
    codec,
    topCodec,
    limits,
    error,
    notice,
  ];
}
