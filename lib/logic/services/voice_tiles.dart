/// One cell of the voice grid.
///
/// Not the same thing as a participant, which is the assumption this replaces.
/// A shared screen reaches the room by one of two routes, and only one of them
/// arrives as a participant of its own:
///
/// - **From a desktop**, the Rust pipeline opens a *second* LiveKit connection
///   whose identity carries a `_screenshare` suffix. One participant, one
///   tile, and the suffix says which kind.
/// - **From a phone**, LiveKit's own `setScreenShareEnabled` publishes a
///   screenshare track on the connection the caller already has. The identity
///   is unchanged, so a grid that reads the suffix sees an ordinary
///   participant — and a tile that then looks only for a camera track finds
///   nothing to draw. That is why a screen shared from a phone was invisible
///   to everyone, the sharer included.
///
/// So the kind is decided by what a participant *publishes*, and a participant
/// can be entitled to two cells: themselves, and their screen.
class VoiceTile<T> {
  final T participant;
  final bool isScreenshare;

  const VoiceTile({required this.participant, required this.isScreenshare});
}

/// The cells to draw for [participants], in a stable order.
///
/// Generic over the participant type so the rule can be tested without a live
/// LiveKit room: callers say how to read an identity and whether a screenshare
/// track is published, and get back what to draw.
List<VoiceTile<T>> voiceTilesFor<T>(
  Iterable<T> participants, {
  required bool Function(T) hasScreenshareIdentity,
  required bool Function(T) publishesScreenshare,
}) {
  final tiles = <VoiceTile<T>>[];
  for (final participant in participants) {
    if (hasScreenshareIdentity(participant)) {
      // A connection that exists only to carry a screen. It has no camera and
      // no microphone, so it is one cell and that cell is the share.
      tiles.add(VoiceTile(participant: participant, isScreenshare: true));
      continue;
    }
    tiles.add(VoiceTile(participant: participant, isScreenshare: false));
    if (publishesScreenshare(participant)) {
      // The same person, twice: their camera or avatar, and their screen.
      // Ordered after their own cell so a share appears beside its owner
      // rather than at the far end of the grid.
      tiles.add(VoiceTile(participant: participant, isScreenshare: true));
    }
  }
  return tiles;
}
