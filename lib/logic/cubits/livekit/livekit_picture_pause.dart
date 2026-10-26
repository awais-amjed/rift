part of 'livekit_cubit.dart';

/// Watched streams' pictures, turned off while nobody can see Rift:
/// minimised, hidden to the tray, or covered by another app's window
/// (`AppSeenListener` says which).
///
/// Every decoded frame redraws the whole window, whether or not it is on
/// screen. On a laptop's Windows, watching cost 117% of a core in front and
/// as much minimised or behind a game (`CALLS.md`, *Watching while Rift
/// cannot be seen*). The stream stays watched: the picture is turned off as
/// a deafen turns off a voice, so the server stops sending it and there is
/// nothing to decode or draw, and the sound plays on. Stopping watching
/// instead would drop the sound and tell the sharer you left.
mixin _PicturePauseMixin on Cubit<LiveKitState> {
  /// Whether Rift can be seen, as last told by [setAppSeen].
  bool _appSeen = true;

  /// Rift can or cannot be seen now; pictures pause and come back with it.
  void setAppSeen(bool seen) {
    if (_appSeen == seen) return;
    _appSeen = seen;
    HelperMethods.printDebug(
      seen
          ? '[LiveKit] Rift can be seen; stream pictures back on'
          : '[LiveKit] Rift cannot be seen; stream pictures off',
    );
    _syncPictureReception();
  }

  /// Brings every stream's picture in line with [_appSeen]. It runs with
  /// every roster sync, so a picture subscribed while Rift is hidden starts
  /// off. Cheap when nothing changed: both calls return at once then.
  void _syncPictureReception() {
    final room = state.room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.source != TrackSource.screenShareVideo) continue;
        // Handed back to adaptive stream rather than turned on: `enable()`
        // would keep the picture coming for good, drawn anywhere or not.
        if (_appSeen) {
          unawaited(pub.clearEnabled());
        } else if (pub.subscribed) {
          unawaited(pub.disable());
        }
      }
    }
  }
}
