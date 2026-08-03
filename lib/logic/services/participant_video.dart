import 'package:livekit_client/livekit_client.dart';

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
}
