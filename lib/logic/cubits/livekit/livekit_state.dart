part of 'livekit_cubit.dart';

enum LiveKitConnectionState { disconnected, connecting, connected, error }

class LiveKitState {
  final LiveKitConnectionState connectionState;
  final Room? room;
  final String? currentChannelId;
  final ConnectionFailure? failure;
  final List<Participant> participants;

  /// **The user's own mic toggle, and nothing else.** Not whether the mic is
  /// actually live — deafening yourself and being muted by a moderator both
  /// stop transmission without touching this, so that lifting either one
  /// returns the mic to the state its owner last chose. Read [isMicOn] to draw
  /// a button; read this only to answer "did they mute themselves".
  final bool isMicEnabled;

  final bool isCameraEnabled;
  final bool isScreenSharing;

  /// The user's own deafen toggle. See [isDeafenedEffective] for "deafened for
  /// any reason".
  final bool isDeafened;

  final bool isPushToTalkPressed;
  final Set<String> subscribedScreenshares;

  /// Moderation imposed on *us*, read off our own participant metadata — the
  /// same channel every other client learns it from.
  final bool isServerMuted;
  final bool isServerDeafened;

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
    this.isServerMuted = false,
    this.isServerDeafened = false,
  });

  /// Whether the microphone is live: the user wants it on, hasn't deafened
  /// themselves, and no moderator has taken it away.
  bool get isMicOn =>
      isMicEnabled && !isDeafened && !isServerMuted && !isServerDeafened;

  /// Deafened for any reason — their own choice or a moderator's.
  bool get isDeafenedEffective => isDeafened || isServerDeafened;

  /// Whether a moderator is holding the mic or the ears, which is what makes
  /// the local controls unusable rather than merely off.
  bool get isModerated => isServerMuted || isServerDeafened;

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
    bool? isServerMuted,
    bool? isServerDeafened,
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
      isServerMuted: isServerMuted ?? this.isServerMuted,
      isServerDeafened: isServerDeafened ?? this.isServerDeafened,
    );
  }
}
