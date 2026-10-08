part of 'livekit_cubit.dart';

/// Where the call connection stands. The call grid picks its view from this.
enum LiveKitConnectionState { disconnected, connecting, connected, error }

/// The current call: the room, who is in it, and this device's own toggles.
/// Emitted on every speaking change, so a builder that shows only some of it
/// filters with `buildWhen`.
class LiveKitState extends Equatable {
  final LiveKitConnectionState connectionState;
  final Room? room;
  final String? currentChannelId;

  /// The DM call this device is in, when the call is one. Never set together
  /// with [currentChannelId]: a call is in a channel or between two people.
  final DmCallPlace? dmCall;

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

  /// The settings mic test is running. It plays the microphone back to you,
  /// so for its length you are muted and deafened in every call — nobody hears
  /// you testing, and the call does not talk over your own voice. Neither of
  /// your own toggles is touched, so stopping the test hands back exactly
  /// what you had.
  final bool isMicTesting;

  final bool isPushToTalkPressed;
  final Set<String> subscribedScreenshares;

  /// Moderation imposed on *us*, read off our own participant metadata — the
  /// same channel every other client learns it from.
  final bool isServerMuted;
  final bool isServerDeafened;

  /// When this call reached [LiveKitConnectionState.connected], so every
  /// timer drawn for it — the call's own header and the bar that stands in
  /// for it elsewhere — counts from the same moment rather than from whenever
  /// each happened to be built. Null whenever the state is anything else.
  final DateTime? connectedAt;

  /// Which LiveKit this call is actually on, as the mint named it.
  ///
  /// The address rather than the region's name, because the address is what
  /// the token carried and the name is something a client looks up — and an
  /// operator may rename a region while somebody is in a call on it.
  final String? connectedLivekitUrl;

  const LiveKitState({
    this.connectionState = LiveKitConnectionState.disconnected,
    this.room,
    this.currentChannelId,
    this.dmCall,
    this.failure,
    this.participants = const [],
    this.isMicEnabled = true,
    this.isCameraEnabled = false,
    this.isScreenSharing = false,
    this.isDeafened = false,
    this.isMicTesting = false,
    this.isPushToTalkPressed = false,
    this.subscribedScreenshares = const {},
    this.isServerMuted = false,
    this.isServerDeafened = false,
    this.connectedAt,
    this.connectedLivekitUrl,
  });

  /// In a call of either kind, connected or on the way.
  bool get inCall => currentChannelId != null || dmCall != null;

  /// One name for the call this device is in, whichever kind: the channel's
  /// id, or `dm:<callId>`. What a share records as the call it belongs to.
  String? get callKey =>
      currentChannelId ?? (dmCall == null ? null : 'dm:${dmCall!.callId}');

  /// Whether there is no call here: never joined, left, or a join that
  /// failed.
  bool get isCallOver =>
      connectionState == LiveKitConnectionState.error ||
      connectionState == LiveKitConnectionState.disconnected;

  /// Whether this is no longer the call [previous] was: another one, none,
  /// or a join that failed. What a share, which is part of being in the
  /// call, has to follow.
  bool leftCall(LiveKitState previous) =>
      callKey != previous.callKey || (isCallOver && !previous.isCallOver);

  /// Whether the microphone is live: the user wants it on, hasn't deafened
  /// themselves, isn't testing it, and no moderator has taken it away.
  bool get isMicOn =>
      isMicEnabled && !isSelfDeafened && !isServerMuted && !isServerDeafened;

  /// Deafened by this device — their own choice, or the mic test. What the
  /// rest of the call is told.
  bool get isSelfDeafened => isDeafened || isMicTesting;

  /// Deafened for any reason — their own choice, the mic test, or a
  /// moderator's.
  bool get isDeafenedEffective => isSelfDeafened || isServerDeafened;

  /// Whether a moderator is holding the mic or the ears, which is what makes
  /// the local controls unusable rather than merely off.
  bool get isModerated => isServerMuted || isServerDeafened;

  /// Why the voice controls won't move, or null when nothing is holding them.
  ///
  /// The button already carries this as a tooltip, which is no use at all on a
  /// phone: there is no hover, so a moderated user taps mute, watches nothing
  /// happen, and has been given no reason to think anything other than that
  /// the app is broken. The control bar shows this on tap instead.
  ///
  /// Deafen is reported ahead of mute because it is the stronger of the two
  /// and it takes the mic with it — saying "muted" to someone who also can't
  /// hear anything answers the smaller half of their question.
  String? get moderationNotice {
    if (isServerDeafened) {
      return 'A moderator has deafened you on this server. You can\'t turn '
          'your mic or sound back on until they undo it.';
    }
    if (isServerMuted) {
      return 'A moderator has muted you on this server. You can\'t unmute '
          'yourself until they undo it.';
    }
    return null;
  }

  LiveKitState copyWith({
    LiveKitConnectionState? connectionState,
    Room? room,
    String? currentChannelId,
    DmCallPlace? dmCall,
    ConnectionFailure? failure,
    List<Participant>? participants,
    bool? isMicEnabled,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool? isDeafened,
    bool? isMicTesting,
    bool? isPushToTalkPressed,
    Set<String>? subscribedScreenshares,
    bool? isServerMuted,
    bool? isServerDeafened,
    DateTime? connectedAt,
    String? connectedLivekitUrl,
    bool clearRoom = false,
    bool clearChannelId = false,
    bool clearDmCall = false,
    bool clearFailure = false,
  }) {
    final nextConnection = connectionState ?? this.connectionState;
    return LiveKitState(
      connectionState: nextConnection,
      room: clearRoom ? null : (room ?? this.room),
      currentChannelId: clearChannelId
          ? null
          : (currentChannelId ?? this.currentChannelId),
      dmCall: clearDmCall ? null : (dmCall ?? this.dmCall),
      failure: clearFailure ? null : (failure ?? this.failure),
      participants: participants ?? this.participants,
      isMicEnabled: isMicEnabled ?? this.isMicEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isDeafened: isDeafened ?? this.isDeafened,
      isMicTesting: isMicTesting ?? this.isMicTesting,
      isPushToTalkPressed: isPushToTalkPressed ?? this.isPushToTalkPressed,
      subscribedScreenshares:
          subscribedScreenshares ?? this.subscribedScreenshares,
      isServerMuted: isServerMuted ?? this.isServerMuted,
      isServerDeafened: isServerDeafened ?? this.isServerDeafened,
      // Tied to the connection rather than cleared by hand at each of the
      // places a call can end, so no path out of a call can leave a stale one.
      connectedAt: nextConnection == LiveKitConnectionState.connected
          ? (connectedAt ?? this.connectedAt)
          : null,
      // Tied to the connection for the same reason: an address kept after a
      // call ended would name a region the next one may not be on.
      connectedLivekitUrl: nextConnection == LiveKitConnectionState.connected
          ? (connectedLivekitUrl ?? this.connectedLivekitUrl)
          : null,
    );
  }

  @override
  List<Object?> get props => [
    connectionState,
    room,
    currentChannelId,
    dmCall,
    failure,
    participants,
    isMicEnabled,
    isCameraEnabled,
    isScreenSharing,
    isDeafened,
    isMicTesting,
    isPushToTalkPressed,
    SetProp(subscribedScreenshares),
    isServerMuted,
    isServerDeafened,
    connectedAt,
    connectedLivekitUrl,
  ];
}
