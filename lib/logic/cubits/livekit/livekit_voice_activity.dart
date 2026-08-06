part of 'livekit_cubit.dart';

/// Local microphone monitor: measures the mic level and drives the speaking
/// indicator, the settings meter and the noise gate from it.
///
/// The level comes from the microphone's raw PCM, tapped with
/// [AudioTrack.addAudioRenderer] and reduced to one number per frame by
/// [PcmLevel]. It runs whenever the mic is live — not only when gating is on —
/// because the speaking glow needs it either way.
///
/// It used to come from an [AudioVisualizer] instead, whose normalised band
/// peak is a display value with no defined relationship to loudness: a quiet
/// room read about 0.03 and a raised voice about 0.25, so everything the user
/// might want to threshold between was crowded into the bottom tenth of the
/// range. Every attempt at a usable slider was really an attempt to compensate
/// for that. [PcmLevel] measures dBFS instead, which spreads silence and speech
/// across the whole scale, and lets the threshold be an ordinary linear
/// fraction of it.
///
/// **Speaking**: LiveKit's `isSpeaking` comes from the server's active-speaker
/// detection, which reports only the loudest few participants on a fixed
/// interval; normal-volume speech frequently never lit the indicator. For the
/// local user the mic level is right here, so [SpeechDetector] decides it
/// locally and immediately. Remote participants still use the server's view.
///
/// **Gating** lives in [_VoiceGateMixin]; this mixin only feeds it levels.
mixin _VoiceActivityMixin on Cubit<LiveKitState> {
  void _syncParticipants();
  bool get _monitorActive;
  LocalTrackPublication? _localMicPublication();
  bool get _gateActive;
  void _feedGate(double level, DateTime now);
  Future<void> _primeGate();
  Future<void> _releaseGate();
  void _noteMicFrame(DateTime now);
  void _cancelVadWatchdog();

  CancelListenFunc? _vadRendererCancel;
  String? _vadTrackId; // media-stream track id the renderer is bound to

  final SpeechDetector _speechDetector = SpeechDetector();

  /// Whether the local user is speaking right now, decided from the mic level.
  /// Cubit-internal — `_syncParticipants` reads it for the local participant.
  bool get localIsSpeaking => _speechDetector.isSpeaking;

  final StreamController<double> _micLevelController =
      StreamController<double>.broadcast();

  /// The live microphone level, 0–1 on [PcmLevel]'s scale, from the tap
  /// already running for the gate and the speaking indicator.
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

  /// Whether [micLevels] is currently carrying anything — i.e. the call is
  /// capturing, so a meter can read it instead of opening its own microphone.
  bool get isMicLevelAvailable => _monitorActive && _vadRendererCancel != null;

  /// Thins [micLevels] down to a paintable rate. The gate and the speaking
  /// detector still see every frame.
  final LevelThrottle _micLevelThrottle = LevelThrottle();

  /// Serialises every monitor lifecycle step.
  ///
  /// [_updateVoiceActivityMonitor] is fired from a dozen places — every mute,
  /// unmute, deafen, push-to-talk change, threshold change and connect —
  /// several of them unawaited, and it awaits while tearing the old tap down.
  /// Two overlapping runs would both reach the attach below, and only the last
  /// one's cancel function would be stored. The other is left attached to the
  /// mic track with nothing holding a reference to remove it.
  ///
  /// That orphan is the leave-hang. It outlives the track it is sinking, so
  /// disposing the room tears the track out from under a live native sink,
  /// and the plugin's audio thread is left holding a freed lock. Hence both
  /// ways in: mute/unmute a few times, or connect somewhere new — anything
  /// that runs two of these close enough together.
  final SerialQueue _vadQueue = SerialQueue(label: '[LiveKit] voice activity');

  /// Attaches or detaches the monitor to match the current settings and mic
  /// track. Safe to call repeatedly — after any mic transmission change or
  /// relevant setting change.
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
      await _releaseGate();
      return;
    }

    final trackId = track.mediaStreamTrack.id;
    if (_vadRendererCancel != null && _vadTrackId == trackId) {
      // Already watching this track — just reconcile the gate, since the
      // threshold or push-to-talk may have changed under us.
      if (!_gateActive) await _releaseGate();
      return;
    }

    // A different (or first) mic track — rebind the tap to it. The mic
    // publication's track is always a LocalAudioTrack (an AudioTrack).
    await _teardownMonitor();
    _vadTrackId = trackId;
    _vadRendererCancel = (track as AudioTrack).addAudioRenderer(
      onFrame: _onAudioFrame,
      options: micTapFormat,
    );
    await _primeGate();
  }

  void _onAudioFrame(AudioFrame frame) {
    if (!_monitorActive) return;
    final level = PcmLevel.fromInt16(frame.data);
    final now = DateTime.now();

    // Speaking indicator — independent of whether the gate is in use.
    if (_speechDetector.update(level, now)) _syncParticipants();

    _emitMicLevel(level, now);

    // This frame is proof the mic is still audible, whatever the gate is doing.
    _noteMicFrame(now);

    _feedGate(level, now);
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
    // No tap means no frames, and a countdown with nothing to reset it would
    // fire on a gate that is already being taken down.
    _cancelVadWatchdog();

    await cancel?.call();
    // A muted mic must not leave the glow stuck on.
    if (_speechDetector.reset()) _syncParticipants();
  }
}
