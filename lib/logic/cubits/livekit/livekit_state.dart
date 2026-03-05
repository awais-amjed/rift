part of 'livekit_cubit.dart';

enum LiveKitConnectionState { disconnected, connecting, connected, error }

class LiveKitState {
  final LiveKitConnectionState connectionState;
  final Room? room;
  final String? currentChannelId;
  final String? error;
  final List<Participant> participants;
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isScreenSharing;

  const LiveKitState({
    this.connectionState = LiveKitConnectionState.disconnected,
    this.room,
    this.currentChannelId,
    this.error,
    this.participants = const [],
    this.isMicEnabled = true,
    this.isCameraEnabled = false,
    this.isScreenSharing = false,
  });

  LiveKitState copyWith({
    LiveKitConnectionState? connectionState,
    Room? room,
    String? currentChannelId,
    String? error,
    List<Participant>? participants,
    bool? isMicEnabled,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool clearRoom = false,
    bool clearChannelId = false,
    bool clearError = false,
  }) {
    return LiveKitState(
      connectionState: connectionState ?? this.connectionState,
      room: clearRoom ? null : (room ?? this.room),
      currentChannelId: clearChannelId
          ? null
          : (currentChannelId ?? this.currentChannelId),
      error: clearError ? null : (error ?? this.error),
      participants: participants ?? this.participants,
      isMicEnabled: isMicEnabled ?? this.isMicEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
    );
  }
}
