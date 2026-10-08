part of 'livekit_cubit.dart';

/// Windows only: keeping the microphone alive after the last voice leaves.
///
/// With echo cancellation on, WebRTC's Windows device module records through
/// Windows' own echo canceller, which hands back microphone audio only while
/// something is being played out. WebRTC itself starts playout before
/// recording when a send stream is added, but it also *stops* playout as soon
/// as the last receive stream goes — while still sending. The capture thread
/// then dies ("capturing thread has ended prematurely") and the mic sends
/// silence for the rest of the call. Muting and unmuting does not bring it
/// back: restarting the recording alone is refused while nothing plays.
///
/// Seen as: two people in a call, one leaves, and whoever joins next hears
/// nothing from the one who stayed until they rejoin.
///
/// What does bring it back is what a join does — publishing the mic afresh,
/// which makes WebRTC start playout and then recording in the order the echo
/// canceller needs. So once the last remote audio is gone, the mic is marked
/// for that, and republished: straight away if it is open — transmitting, or
/// waiting on push-to-talk (after [K.captureReviveDelay], so WebRTC has
/// stopped playout first) — otherwise the next time it opens.
mixin _CaptureReviveMixin on Cubit<LiveKitState> {
  /// Republishes the mic if it is open; the next unmute does it otherwise.
  void _reviveCaptureIfCapturing();

  /// Whether any remote audio has been received since the mic was last
  /// published — without it, there is no playout for WebRTC to stop.
  bool _heardRemoteAudio = false;

  /// Set once playout may have stopped under a recording mic.
  bool _captureMayBeDead = false;
  Timer? _captureReviveTimer;

  /// A remote audio track arrived. Called for every subscription.
  // Its callers are in `_RoomEventsMixin`, where the call resolves to that
  // mixin's abstract declaration — which the unused-element check can't follow.
  // ignore: unused_element
  void _onRemoteAudioArrived(RemoteTrackPublication publication) {
    if (!HostPlatform.recordsThroughOsEchoCanceller) return;
    if (publication.kind == TrackType.AUDIO) _heardRemoteAudio = true;
  }

  /// Remote audio may have gone: an unsubscription, or somebody leaving.
  ///
  /// Checked after [K.captureReviveDelay] rather than now: the event comes
  /// before WebRTC removes the receive stream, and a mic republished before
  /// that would only have its playout stopped under it again.
  // See [_onRemoteAudioArrived] on the ignore.
  // ignore: unused_element
  void _onRemoteAudioMayHaveGone() {
    if (!HostPlatform.recordsThroughOsEchoCanceller) return;
    if (!_heardRemoteAudio) return;
    _captureReviveTimer?.cancel();
    _captureReviveTimer = Timer(K.captureReviveDelay, () {
      final room = state.room;
      if (room == null || _remoteAudioCount(room) > 0) return;
      _heardRemoteAudio = false;
      _captureMayBeDead = true;
      _reviveCaptureIfCapturing();
    });
  }

  /// Whether the mic has to be published afresh rather than unmuted, and
  /// forgets it — the caller is about to.
  bool _takeCaptureRevive() {
    if (!_captureMayBeDead) return false;
    _captureMayBeDead = false;
    return true;
  }

  // Called from `_LiveKitLeaveMixin`; see [_onRemoteAudioArrived] on the ignore.
  // ignore: unused_element
  void _resetCaptureRevive() {
    _captureReviveTimer?.cancel();
    _captureReviveTimer = null;
    _heardRemoteAudio = false;
    _captureMayBeDead = false;
  }

  static int _remoteAudioCount(Room room) => room.remoteParticipants.values
      .expand((p) => p.audioTrackPublications)
      .where((pub) => pub.subscribed)
      .length;
}
