part of 'livekit_cubit.dart';

/// Stream pictures, held off unless somebody is looking: an unwatched stream's
/// always, a stream the Rust watch connection holds always, and a watched one
/// while nobody can see Rift: minimised, hidden to the tray, or covered by
/// another app's window (`AppSeenListener` says which).
///
/// Held, never unsubscribed. Subscribing to a picture again opens a second
/// receiver under the first one's id, and its frame cryptor goes on the wrong
/// one, so Watch drew the stream still encrypted: a green screen (`CALLS.md`,
/// *Receiving a stream's picture*).
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
    // The watch connection's pictures, the same way.
    if (RustWatch.available) unawaited(RustWatch.setPicturesOn(seen));
  }

  /// How long a picture stays off for [renewPicture]. The server applies a
  /// subscriber's "off" 100 ms after it arrives, and an "on" arriving first
  /// cancels it (`SubscribedTrack.UpdateSubscriberSettings`, livekit-server
  /// 1.13), so the pause must outlast that and the trip there.
  static const _renewPause = Duration(milliseconds: 300);

  /// Pictures off for a moment by [renewPicture], by track sid, which the
  /// roster sync leaves alone: its `clearEnabled` would cancel the pause.
  final Set<String> _renewing = {};

  /// Has the sharer send a fresh keyframe of [track], by turning its picture
  /// off for a moment: the server asks the sharer for one when a subscriber
  /// turns a picture back on. A stream watched through this room is
  /// decrypted only once it is subscribed, after its first keyframe has gone
  /// by, and nothing else asks for another (`DecryptedVideo`).
  ///
  /// Asked for on a picture already decrypting too, when Watch turns it on
  /// again: nothing else says when its keyframe has been decoded.
  Future<void> renewPicture(RemoteVideoTrack track) async {
    final pub = _publicationOf(track);
    if (pub == null || !_appSeen || !_renewing.add(pub.sid)) return;
    final sid = pub.sid;
    try {
      await pub.disable();
      await Future<void>.delayed(_renewPause);
    } finally {
      _renewing.remove(sid);
      // Back to whatever it should be now; Rift may have gone out of sight.
      _syncPictureReception();
    }
  }

  RemoteTrackPublication? _publicationOf(RemoteVideoTrack track) {
    final room = state.room;
    if (room == null) return null;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track == track) return pub;
      }
    }
    return null;
  }

  /// Tracks whose frame cryptor has said it is decrypting. It says so once,
  /// and a held picture may have said so long before anybody watched it.
  final Expando<bool> _decrypting = Expando('decrypting picture');

  /// Tracks whose picture has come clean since they were last watched. The
  /// same track is drawn by a new widget whenever its tile moves between full
  /// size and the stage, and that is no reason to cover it again.
  final Expando<bool> _clean = Expando('clean picture');

  // Called from `_RoomEventsMixin` through its abstract declaration, which
  // the unused-element check can't follow.
  // ignore: unused_element
  void _noteDecryption(TrackE2EEStateEvent e) {
    final track = e.publication.track;
    if (track != null) _decrypting[track] = e.state == E2EEState.kOk;
  }

  bool isDecrypting(VideoTrack track) => _decrypting[track] ?? false;
  bool isPictureClean(VideoTrack track) => _clean[track] ?? false;
  void markPictureClean(VideoTrack track) => _clean[track] = true;

  /// Brings every stream's picture in line with who is looking. It runs with
  /// every roster sync, so a picture that arrives unwatched, or while Rift is
  /// hidden, starts off. Cheap when nothing changed: both calls return at once
  /// then.
  void _syncPictureReception() {
    final room = state.room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.source != TrackSource.screenShareVideo) continue;
        final identity = participant.identity;
        final watched = state.subscribedScreenshares.contains(identity);
        final track = pub.track;
        if (!watched && track != null) _clean[track] = null;
        if (_renewing.contains(pub.sid)) continue;
        // Handed back to adaptive stream rather than turned on: `enable()`
        // would keep the picture coming for good, drawn anywhere or not.
        // Said before any track is here as well: the server keeps it for
        // when the track arrives.
        if (_appSeen &&
            watched &&
            !state.watchedPictures.containsKey(identity)) {
          unawaited(pub.clearEnabled());
        } else {
          unawaited(pub.disable());
        }
      }
    }
  }
}
