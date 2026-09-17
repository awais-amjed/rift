import 'package:livekit_client/livekit_client.dart';

import '../../data/participant_identity.dart';
import 'voice_tiles.dart';

/// [voiceTilesFor], bound to a live LiveKit room.
///
/// The rule itself is generic so it can be tested without a room; this is the
/// one place that says what its two questions mean for a real [Participant].
/// Two places would be two chances to get the phone-shares-its-screen case
/// wrong again, and the grid and the picture-in-picture window both need it.
List<VoiceTile<Participant>> roomVoiceTiles(
  Iterable<Participant> participants,
) {
  return voiceTilesFor(
    participants,
    shareKindOf: (p) {
      if (ParticipantIdentity.isScreenshare(p.identity)) {
        return VoiceTileKind.screenshare;
      }
      if (ParticipantIdentity.isSoundShare(p.identity)) {
        return VoiceTileKind.soundShare;
      }
      return null;
    },
    publishesScreenshare: (p) => p.videoTrackPublications.any(
      (pub) => pub.source == TrackSource.screenShareVideo,
    ),
  );
}
