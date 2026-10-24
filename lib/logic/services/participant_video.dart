import 'package:livekit_client/livekit_client.dart';

import '../../data/participant_identity.dart';

/// Which of a participant's video publications a tile should render.
class ParticipantVideo {
  const ParticipantVideo._();

  /// The publication to show, or null for the avatar fallback.
  ///
  /// A screenshare tile wants the share track whether or not it is muted —
  /// a paused share still holds its slot. A camera tile wants the opposite:
  /// a muted camera is the same as no camera, so it falls back to the avatar.
  static TrackPublication? activePublication(
    Iterable<TrackPublication> publications, {
    required bool isScreenshare,
  }) {
    for (final pub in publications) {
      if (pub.track == null) continue;
      if (isScreenshare) {
        if (pub.source == TrackSource.screenShareVideo) return pub;
      } else {
        if (pub.source == TrackSource.camera && !pub.muted) return pub;
      }
    }
    return null;
  }

  /// The camera of whoever is sharing [shareIdentity], to float over the
  /// stream while it is watched, or null when their camera is off.
  ///
  /// A desktop's stream is a connection of its own beside the one with the
  /// camera ([ParticipantIdentity.baseOf] finds it); a phone streams on the
  /// connection it is already in the call on, so the two are one. Never your
  /// own: you know what you look like.
  static VideoTrack? ownerCamera(Room room, String shareIdentity) {
    final owner = ParticipantIdentity.baseOf(shareIdentity);
    final mine = room.localParticipant?.identity;
    if (mine != null && owner == mine) return null;
    final person = room.remoteParticipants.values
        .where((p) => p.identity == owner)
        .firstOrNull;
    if (person == null) return null;
    final track = activePublication(
      person.videoTrackPublications,
      isScreenshare: false,
    )?.track;
    return track is VideoTrack ? track : null;
  }
}
