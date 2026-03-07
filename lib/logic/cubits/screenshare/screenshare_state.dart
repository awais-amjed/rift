part of 'screenshare_cubit.dart';

enum ScreenshareStatus { idle, connecting, sharing, stopping, error }

class ScreenshareState {
  final ScreenshareStatus status;
  final String? channelId;
  final ScreenShareSettings? settings;
  final String? error;

  const ScreenshareState({
    this.status = ScreenshareStatus.idle,
    this.channelId,
    this.settings,
    this.error,
  });

  bool get isSharing => status == ScreenshareStatus.sharing;

  bool get isConnecting => status == ScreenshareStatus.connecting;

  bool get hasError => status == ScreenshareStatus.error;

  ScreenshareState copyWith({
    ScreenshareStatus? status,
    String? channelId,
    ScreenShareSettings? settings,
    String? error,
    bool clearChannelId = false,
    bool clearSettings = false,
    bool clearError = false,
  }) {
    return ScreenshareState(
      status: status ?? this.status,
      channelId: clearChannelId ? null : (channelId ?? this.channelId),
      settings: clearSettings ? null : (settings ?? this.settings),
      error: clearError ? null : (error ?? this.error),
    );
  }
}
