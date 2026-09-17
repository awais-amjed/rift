/// What one cell of the voice grid is showing.
enum VoiceTileKind {
  /// Somebody in the call: their camera, or their avatar.
  person,

  /// A shared screen or window.
  screenshare,

  /// An application's sound, shared without its picture.
  soundShare,
}

/// One cell of the voice grid.
///
/// Not the same thing as a participant, which is the assumption this replaces.
/// A shared screen reaches the room by one of two routes, and only one of them
/// arrives as a participant of its own:
///
/// - **From a desktop**, the Rust pipeline opens a *second* LiveKit connection
///   whose identity carries a `_screenshare` suffix (or `_soundshare`, for a
///   share that is only sound). One participant, one tile, and the suffix says
///   which kind.
/// - **From a phone**, LiveKit's own `setScreenShareEnabled` publishes a
///   screenshare track on the connection the caller already has. The identity
///   is unchanged, so a grid that reads the suffix sees an ordinary
///   participant — and a tile that then looks only for a camera track finds
///   nothing to draw. That is why a screen shared from a phone was invisible
///   to everyone, the sharer included.
///
/// So the kind is decided by what a participant *publishes* as much as by what
/// it is called, and a participant can be entitled to two cells: themselves,
/// and their screen.
class VoiceTile<T> {
  final T participant;
  final VoiceTileKind kind;

  const VoiceTile({required this.participant, required this.kind});

  bool get isScreenshare => kind == VoiceTileKind.screenshare;

  bool get isSoundShare => kind == VoiceTileKind.soundShare;
}

/// The cells to draw for [participants], in a stable order.
///
/// Generic over the participant type so the rule can be tested without a live
/// LiveKit room: callers say what kind of share a connection is (null for an
/// ordinary one) and whether a screenshare track is published, and get back
/// what to draw.
List<VoiceTile<T>> voiceTilesFor<T>(
  Iterable<T> participants, {
  required VoiceTileKind? Function(T) shareKindOf,
  required bool Function(T) publishesScreenshare,
}) {
  final tiles = <VoiceTile<T>>[];
  for (final participant in participants) {
    final shareKind = shareKindOf(participant);
    if (shareKind != null) {
      // A connection that exists only to carry a share. It has no camera and
      // no microphone, so it is one cell and that cell is the share.
      tiles.add(VoiceTile(participant: participant, kind: shareKind));
      continue;
    }
    tiles.add(VoiceTile(participant: participant, kind: VoiceTileKind.person));
    if (publishesScreenshare(participant)) {
      // The same person, twice: their camera or avatar, and their screen.
      // Ordered after their own cell so a share appears beside its owner
      // rather than at the far end of the grid.
      tiles.add(
        VoiceTile(participant: participant, kind: VoiceTileKind.screenshare),
      );
    }
  }
  return tiles;
}
