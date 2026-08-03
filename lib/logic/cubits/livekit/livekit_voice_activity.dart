part of 'livekit_cubit.dart';

/// Local microphone monitor: drives the speaking indicator, and the optional
/// voice-activity gate (noise gate).
///
/// One [AudioVisualizer] on the published mic track supplies the level, and it
/// runs whenever the mic is live — not only when gating is on — because the
/// speaking glow needs it either way.
///
/// **Speaking**: LiveKit's `isSpeaking` comes from the server's active-speaker
/// detection, which reports only the loudest few participants on a fixed
/// interval; normal-volume speech frequently never lit the indicator. For the
/// local user the mic level is right here, so [SpeechDetector] decides it
/// locally and immediately. Remote participants still use the server's view.
///
/// **Gating**: while in voice-activity mode (push-to-talk off) with a non-zero
/// threshold, the mic only transmits at or above the user's threshold. The
/// gate toggles the track's underlying media-stream `enabled` flag: for audio
/// tracks that transmits silence to peers while local sinks (including this
/// visualizer) still receive the live mic, so the gate can always hear speech
/// and re-open — no deadlock, and no re-acquiring the mic.
mixin _VoiceActivityMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  void _syncParticipants();

  AudioVisualizer? _vadVisualizer;
  EventsListener<AudioVisualizerEvent>? _vadListener;
  String? _vadTrackId; // media-stream track id the visualizer is bound to
  bool _vadGateOpen = true; // whether the mic is currently transmitting
  DateTime? _vadHoldUntil; // keep the gate open until this instant

  final SpeechDetector _speechDetector = SpeechDetector();

  /// Whether the local user is speaking right now, decided from the mic level.
  /// Cubit-internal — `_syncParticipants` reads it for the local participant.
  bool get localIsSpeaking => _speechDetector.isSpeaking;

  // Keep transmitting briefly after the level drops so word endings and short
  // pauses aren't clipped.
  static const _vadHold = Duration(milliseconds: 300);

  LocalTrackPublication? _localMicPublication() {
    final pubs = state.room?.localParticipant?.audioTrackPublications;
    if (pubs == null) return null;
    for (final pub in pubs) {
      if (pub.source == TrackSource.microphone) return pub;
    }
    return null;
  }

  /// Whether the mic level is worth watching at all.
  bool get _monitorActive {
    if (state.connectionState != LiveKitConnectionState.connected) return false;
    return state.isMicEnabled && !state.isDeafened;
  }

  /// Whether the noise gate should be applied on top of monitoring.
  bool get _gateActive {
    if (!_monitorActive) return false;
    // Push-to-talk already decides transmission; don't also gate.
    if (_appCubit.state.pushToTalkEnabled) return false;
    return _appCubit.state.voiceActivityThreshold > 0;
  }

  /// Attaches or detaches the monitor to match the current settings and mic
  /// track. Safe to call repeatedly — after any mic transmission change or
  /// relevant setting change.
  Future<void> _updateVoiceActivityMonitor() async {
    final track = _localMicPublication()?.track;

    if (!_monitorActive || track == null) {
      await _stopVoiceActivityMonitor();
      // Never leave the mic muted by a closed gate once gating is off.
      if (track != null) track.mediaStreamTrack.enabled = true;
      _vadGateOpen = true;
      return;
    }

    final trackId = track.mediaStreamTrack.id;
    if (_vadVisualizer != null && _vadTrackId == trackId) {
      // Already watching this track — just reconcile the gate, since the
      // threshold or push-to-talk may have changed under us.
      if (!_gateActive) {
        _vadGateOpen = true;
        track.mediaStreamTrack.enabled = true;
      }
      return;
    }

    // A different (or first) mic track — rebind the visualizer to it. The mic
    // publication's track is always a LocalAudioTrack (an AudioTrack).
    await _stopVoiceActivityMonitor();
    final visualizer = createVisualizer(
      track as AudioTrack,
      options: const AudioVisualizerOptions(barCount: 7, centeredBands: false),
    );
    _vadVisualizer = visualizer;
    _vadTrackId = trackId;
    _vadListener = visualizer.createListener()
      ..on<AudioVisualizerEvent>(_onVadEvent);

    // When gating, start closed until we actually hear something above the
    // threshold; when only watching levels, the mic transmits as usual.
    _vadGateOpen = !_gateActive;
    _vadHoldUntil = null;
    track.mediaStreamTrack.enabled = _vadGateOpen;
    await visualizer.start();
  }

  void _onVadEvent(AudioVisualizerEvent e) {
    if (!_monitorActive) return;
    final bands = e.event.whereType<num>().map((n) => n.toDouble());
    if (bands.isEmpty) return;
    final peak = bands.reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
    final now = DateTime.now();

    // Speaking indicator — independent of whether the gate is in use.
    if (_speechDetector.update(peak, now)) _syncParticipants();

    if (!_gateActive) return;
    final threshold = _appCubit.state.voiceActivityThreshold;
    if (peak >= threshold) {
      _vadHoldUntil = now.add(_vadHold);
      _setVadGate(true);
    } else if (_vadHoldUntil == null || now.isAfter(_vadHoldUntil!)) {
      _setVadGate(false);
    }
  }

  void _setVadGate(bool open) {
    if (_vadGateOpen == open) return;
    _vadGateOpen = open;
    final track = _localMicPublication()?.track;
    if (track != null) track.mediaStreamTrack.enabled = open;
  }

  Future<void> _stopVoiceActivityMonitor() async {
    await _vadListener?.dispose();
    await _vadVisualizer?.stop();
    await _vadVisualizer?.dispose();
    _vadListener = null;
    _vadVisualizer = null;
    _vadTrackId = null;
    _vadHoldUntil = null;
    // A muted mic must not leave the glow stuck on.
    if (_speechDetector.reset()) _syncParticipants();
  }
}
