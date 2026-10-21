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
}
