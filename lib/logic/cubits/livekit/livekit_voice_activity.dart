part of 'livekit_cubit.dart';

/// Local microphone monitor: measures the mic level and drives the speaking
/// indicator and the settings meter from it.
///
/// The level comes from the microphone's raw PCM, tapped with
/// [AudioTrack.addAudioRenderer] and reduced to one number per frame by
/// [PcmLevel]. It runs whenever the mic is live.
///
/// It used to come from an [AudioVisualizer] instead, whose normalised band
/// peak is a display value with no defined relationship to loudness: a quiet
/// room read about 0.03 and a raised voice about 0.25, so speech and silence
/// were crowded into the bottom tenth of the range. [PcmLevel] measures dBFS
/// instead, which spreads them across the whole scale.
///
/// **Speaking**: LiveKit's `isSpeaking` comes from the server's active-speaker
/// detection, which reports only the loudest few participants on a fixed
/// interval; normal-volume speech frequently never lit the indicator. For the
/// local user the mic level is right here, so [SpeechDetector] decides it
/// locally and immediately. Remote participants still use the server's view.
///
/// There used to be a noise gate here too — a user-set threshold below which
/// the mic stopped transmitting. It never worked. Gating the capture track
/// released the microphone on Linux, so the monitor went deaf and the gate
/// could never reopen itself; gating the RTP sender instead left the device
/// alone but libwebrtc ignored the inactive encoding and kept transmitting. It
/// was removed rather than carried as a setting that does nothing.
mixin _VoiceActivityMixin on Cubit<LiveKitState> {
  void _syncParticipants({bool speakingOnly});
  // Signature has to match `_LiveKitConnectionMixin`'s declaration, which this
  // mixin overrides by being applied after it, even though only the no-argument
  // form is called here.
  // ignore: unused_element_parameter
  bool _shouldTransmitMic({bool? micEnabled});

  CancelListenFunc? _vadRendererCancel;
  String? _vadTrackId; // media-stream track id the renderer is bound to

  final SpeechDetector _speechDetector = SpeechDetector();

  /// Whether the local user is speaking right now, decided from the mic level.
  /// Cubit-internal — `_syncParticipants` reads it for the local participant.
  bool get localIsSpeaking => _speechDetector.isSpeaking;

  final StreamController<double> _micLevelController =
      StreamController<double>.broadcast();

  /// The live microphone level, 0–1 on [PcmLevel]'s scale.
  ///
  /// Exposed so the mic test in settings can draw its meter without opening a
  /// second capture of a device this call is already holding. On a Bluetooth
  /// headset there is one HFP stream, and handing it back and forth is both
  /// slow and unreliable — borrowing the levels costs nothing and cannot fail.
  ///
  /// A stream rather than cubit state on purpose: this fires many times a
  /// second, and putting it in [LiveKitState] would rebuild every listener in
  /// the app for a number one settings widget wants.
  Stream<double> get micLevels => _micLevelController.stream;

  /// Whether a meter should read [micLevels] rather than open a microphone of
  /// its own, because this call will be capturing the device while it runs.
  ///
  /// Deliberately **not** [_monitorActive]: that follows what is being
  /// transmitted, and under push-to-talk the answer flips with every keypress.
  /// A meter that asked it would open its own capture during a gap and then
  /// find the call taking the device back the moment the key went down —
  /// which on a Bluetooth headset, with its single HFP stream, is the fight
  /// [micLevels] exists to avoid. The mic being *muted* is different: nothing
  /// is holding the device and nothing is about to, so a meter is welcome to
  /// open it.
  bool get isCallHoldingMic {
    if (state.connectionState != LiveKitConnectionState.connected) return false;
    if (!state.isMicEnabled) return false;
    return !state.isDeafenedEffective && !state.isServerMuted;
  }

  /// Thins [micLevels] down to a paintable rate. The speaking detector still
  /// sees every frame.
  final LevelThrottle _micLevelThrottle = LevelThrottle();

  /// Whether the mic level is worth measuring at all.
  ///
  /// This has to follow what is actually being transmitted, not just the
  /// user's own mic toggle. Push-to-talk leaves [LiveKitState.isMicEnabled]
  /// alone and flips [LiveKitState.isPushToTalkPressed] instead, and releasing
  /// the key mutes the publication rather than removing it. Reading the toggle
  /// therefore stayed true on release, [_applyMonitor] took its "same track,
  /// already attached" early return, and no frames ever arrived to close the
  /// detector's hold window — so letting go mid-word left the glow on for
  /// good, while letting go during a pause looked fine.
  bool get _monitorActive {
    if (state.connectionState != LiveKitConnectionState.connected) return false;
    return _shouldTransmitMic();
  }

  LocalTrackPublication? _localMicPublication() {
    final pubs = state.room?.localParticipant?.audioTrackPublications;
    if (pubs == null) return null;
    for (final pub in pubs) {
      if (pub.source == TrackSource.microphone) return pub;
    }
    return null;
  }

  /// Serialises every monitor lifecycle step.
  ///
  /// [_updateVoiceActivityMonitor] is fired from a dozen places — every mute,
  /// unmute, deafen, push-to-talk change and connect — several of them
  /// unawaited, and it awaits while tearing the old tap down. Two overlapping
  /// runs would both reach the attach below, and only the last one's cancel
  /// function would be stored. The other is left attached to the mic track
  /// with nothing holding a reference to remove it.
  ///
  /// That orphan is the leave-hang. It outlives the track it is sinking, so
  /// disposing the room tears the track out from under a live native sink,
  /// and the plugin's audio thread is left holding a freed lock. Hence both
  /// ways in: mute/unmute a few times, or connect somewhere new — anything
  /// that runs two of these close enough together.
  final SerialQueue _vadQueue = SerialQueue(label: '[LiveKit] voice activity');

  /// Attaches or detaches the monitor to match the current mic track. Safe to
  /// call repeatedly — after any mic transmission change.
  Future<void> _updateVoiceActivityMonitor() => _vadQueue.add(_applyMonitor);

  /// Detaches the monitor. Queued behind any in-flight attach, so teardown
  /// can never run past a half-built tap.
  ///
  /// Its only callers are in `_LiveKitConnectionMixin`, where the call
  /// resolves to that mixin's abstract declaration rather than to this body —
  /// which the unused-element check can't follow across the two mixins.
  // ignore: unused_element
  Future<void> _stopVoiceActivityMonitor() => _vadQueue.add(_teardownMonitor);

  Future<void> _applyMonitor() async {
    final track = _localMicPublication()?.track;

    if (!_monitorActive || track == null) {
      // The private form, not the queued one — this is already running as a
      // queue step, and waiting on the queue from inside it would deadlock.
      await _teardownMonitor();
      return;
    }

    final trackId = track.mediaStreamTrack.id;
    if (_vadRendererCancel != null && _vadTrackId == trackId) return;

    // A different (or first) mic track — rebind the tap to it. The mic
    // publication's track is always a LocalAudioTrack (an AudioTrack).
    await _teardownMonitor();
    _vadTrackId = trackId;
    _vadRendererCancel = (track as AudioTrack).addAudioRenderer(
      onFrame: _onAudioFrame,
      options: micTapFormat,
    );
  }

  void _onAudioFrame(AudioFrame frame) {
    if (!_monitorActive) return;
    final level = PcmLevel.fromInt16(frame.data);
    final now = DateTime.now();

    if (_speechDetector.update(level, now)) {
      _syncParticipants(speakingOnly: true);
    }

    _emitMicLevel(level, now);
  }

  void _emitMicLevel(double level, DateTime now) {
    final published = _micLevelThrottle.add(level, now);
    if (published == null || _micLevelController.isClosed) return;
    _micLevelController.add(published);
  }

  Future<void> _teardownMonitor() async {
    // Take the handle before awaiting anything. Mic changes, settings changes
    // and room teardown all reach here, and a second caller that arrives mid-
    // await would otherwise remove the same renderer twice.
    final cancel = _vadRendererCancel;
    _vadRendererCancel = null;
    _vadTrackId = null;
    _micLevelThrottle.reset();

    await cancel?.call();
    // A muted mic must not leave the glow stuck on.
    if (_speechDetector.reset()) _syncParticipants(speakingOnly: true);
    // Nor a borrowed meter stuck wherever the last frame left it. No more
    // frames are coming, so silence has to be said rather than measured.
    if (!_micLevelController.isClosed) _micLevelController.add(0);
  }
}
