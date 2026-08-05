part of 'livekit_cubit.dart';

enum LiveKitConnectionState { disconnected, connecting, connected, error }

class LiveKitState {
  final LiveKitConnectionState connectionState;
  final Room? room;
  final String? currentChannelId;
  final ConnectionFailure? failure;
  final List<Participant> participants;
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isScreenSharing;
  final bool isDeafened;
  final bool isPushToTalkPressed;
  final Set<String> subscribedScreenshares;

  const LiveKitState({
    this.connectionState = LiveKitConnectionState.disconnected,
    this.room,
    this.currentChannelId,
    this.failure,
    this.participants = const [],
    this.isMicEnabled = true,
    this.isCameraEnabled = false,
    this.isScreenSharing = false,
    this.isDeafened = false,
    this.isPushToTalkPressed = false,
    this.subscribedScreenshares = const {},
  });

  LiveKitState copyWith({
    LiveKitConnectionState? connectionState,
    Room? room,
    String? currentChannelId,
    ConnectionFailure? failure,
    List<Participant>? participants,
    bool? isMicEnabled,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool? isDeafened,
    bool? isPushToTalkPressed,
    Set<String>? subscribedScreenshares,
    bool clearRoom = false,
    bool clearChannelId = false,
    bool clearFailure = false,
  }) {
    return LiveKitState(
      connectionState: connectionState ?? this.connectionState,
      room: clearRoom ? null : (room ?? this.room),
      currentChannelId: clearChannelId
          ? null
          : (currentChannelId ?? this.currentChannelId),
      failure: clearFailure ? null : (failure ?? this.failure),
      participants: participants ?? this.participants,
      isMicEnabled: isMicEnabled ?? this.isMicEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isDeafened: isDeafened ?? this.isDeafened,
      isPushToTalkPressed: isPushToTalkPressed ?? this.isPushToTalkPressed,
      subscribedScreenshares:
          subscribedScreenshares ?? this.subscribedScreenshares,
    );
  }
}
