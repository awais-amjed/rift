part of 'livekit_cubit.dart';

/// What this client receives of each remote audio track, decided in one
/// place ([hearsRemoteAudio]) and applied twice over: the server is told to
/// stop sending what is not heard, and the track is turned off here as well,
/// so it is silent even before the server has acted on it.
///
/// **Audio is disabled, never unsubscribed** — the one exception is your own
/// share, dropped for good. An unsubscribed track gives its slot on the
/// connection back, LiveKit's server hands that slot to the next track to
/// arrive, and the slot keeps the id of the track it was made for. When that
/// first track is subscribed again it gets a second slot under the same id,
/// and flutter_webrtc puts each new track's frame cryptor on the *first* slot
/// with the id it is given. The other slot then plays its frames still
/// encrypted: loud static, on the stream and on every voice that later passes
/// through it, until the call is joined again. Reported Oct 19 2026 after
/// watching a stream; on the local stack it came back in 4 of 12 runs that
/// watched, stopped watching and deafened as the app did, and in none of 12
/// that disabled instead.
mixin _AudioReceptionMixin on Cubit<LiveKitState> {
  void _applyStoredSettings();
  Future<void> retryConnection();

  /// When the receiver check last joined the call again.
  DateTime? _lastReceiverRejoin;

  /// Whether [publication], on [participant] in [room], is one to hear.
  bool _hearsAudio(
    Room room,
    Participant participant,
    TrackPublication publication,
  ) {
    final identity = participant.identity;
    final identities = [
      if (room.localParticipant != null) room.localParticipant!.identity,
      ...room.remoteParticipants.keys,
    ];
    return hearsRemoteAudio(
      deafened: state.isDeafenedEffective,
      stream:
          !ParticipantIdentity.isSoundShare(identity) &&
          (ParticipantIdentity.isScreenshare(identity) ||
              publication.source == TrackSource.screenShareAudio),
      watched: state.subscribedScreenshares.contains(identity),
      ownerless: sharesWithoutOwner(identities).contains(identity),
      someoneElse:
          state.listeningOnlyTo != null &&
          ParticipantIdentity.userIdOf(identity) != state.listeningOnlyTo,
    );
  }

  /// Brings every remote audio track in line with [_hearsAudio]. Cheap when
  /// nothing changed, which is most calls: it runs with every roster sync.
  // Its callers in the other parts resolve to their own abstract
  // declarations, which the unused-element check can't follow.
  // ignore: unused_element
  void _syncAudioReception() {
    final room = state.room;
    if (room == null) return;
    var turnedOn = false;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        if (!pub.subscribed) continue;
        final hear = _hearsAudio(room, participant, pub);
        if (!hear) pub.track?.mediaStreamTrack.enabled = false;
        if (pub.enabled == hear) continue;
        turnedOn |= hear;
        unawaited(hear ? pub.enable() : pub.disable());
      }
    }
    // Back on with the listener's own mute and volume, not simply on.
    if (turnedOn) _applyStoredSettings();
  }

  /// Joins the call again if two of its live audio receivers share an id.
  ///
  /// Holding audio keeps this client from causing that, but a track can still
  /// be subscribed again from outside it, and the frame cryptor then goes on
  /// the wrong receiver. Caught here it is caught early: on the local stack
  /// the shared id was there at join, some fifteen seconds before anyone
  /// heard static. A fresh connection has no shared ids. Not on the web,
  /// which fits a cryptor to the receiver itself rather than finding it by
  /// id.
  ///
  /// Pictures are only logged. They are still unsubscribed while unwatched,
  /// so they can share an id often, and what that costs is one picture.
  // Called from `_RoomEventsMixin` through its abstract declaration, which
  // the unused-element check can't follow.
  // ignore: unused_element
  Future<void> _checkReceivers() async {
    if (kIsWeb) return;
    if (state.connectionState != LiveKitConnectionState.connected) return;
    final room = state.room;
    if (room == null) return;
    // The receivers are the subscriber connection's, which the SDK keeps to
    // itself; the call stats read it the same way (`VoiceStatsCubit`).
    // ignore: invalid_use_of_internal_member
    final pc = room.engine.subscriber?.pc;
    if (pc == null) return;
    final List<rtc.RTCRtpReceiver> receivers;
    try {
      receivers = await pc.getReceivers();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] receiver check failed: $e');
      return;
    }
    List<String> ids(String kind) => [
      for (final r in receivers)
        if (r.track?.kind == kind) r.receiverId,
    ];
    final pictures = sharedReceiverIds(ids('video'));
    if (pictures.isNotEmpty) {
      HelperMethods.printDebug(
        '[LiveKit] video receivers share an id: $pictures',
      );
    }
    final shared = sharedReceiverIds(ids('audio'));
    if (shared.isEmpty) return;
    final now = DateTime.now();
    final last = _lastReceiverRejoin;
    if (last != null && now.difference(last) < K.receiverClashRejoinGap) {
      HelperMethods.printDebug(
        '[LiveKit] audio receivers share an id again ($shared); '
        'not joining again so soon',
      );
      return;
    }
    _lastReceiverRejoin = now;
    HelperMethods.printDebug(
      '[LiveKit] audio receivers share an id ($shared); joining the call '
      'again before it plays static',
    );
    await retryConnection();
  }
}
