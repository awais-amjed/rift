part of 'livekit_cubit.dart';

/// Voice-activity gate (noise gate).
///
/// While connected in voice-activity mode (push-to-talk off) with a non-zero
/// threshold, the local mic only transmits when its input level is at or above
/// the user's threshold. A lightweight audio visualizer on the published mic
/// track supplies the level, and the gate toggles the track's underlying
/// media-stream `enabled` flag: for audio tracks that transmits silence to
/// peers while local sinks (including this visualizer) still receive the live
/// mic, so the gate can always hear speech and re-open — no deadlock, and no
/// re-acquiring the mic.
mixin _VoiceActivityMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;

  AudioVisualizer? _vadVisualizer;
  EventsListener<AudioVisualizerEvent>? _vadListener;
  String? _vadTrackId; // media-stream track id the visualizer is bound to
  bool _vadGateOpen = true; // whether the mic is currently transmitting
  DateTime? _vadHoldUntil; // keep the gate open until this instant

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

  bool get _vadActive {
    if (state.connectionState != LiveKitConnectionState.connected) return false;
    if (!state.isMicEnabled || state.isDeafened) return false;
    // Push-to-talk already decides transmission; don't also gate.
    if (_appCubit.state.pushToTalkEnabled) return false;
    return _appCubit.state.voiceActivityThreshold > 0;
  }

  /// Attaches or detaches the gate to match the current settings and mic track.
  /// Safe to call repeatedly — after any mic transmission change or relevant
  /// setting change.
  Future<void> _updateVoiceActivityMonitor() async {
    final track = _localMicPublication()?.track;

    if (!_vadActive || track == null) {
      await _stopVoiceActivityMonitor();
      // Never leave the mic muted by a closed gate once gating is off.
      if (track != null) track.mediaStreamTrack.enabled = true;
      _vadGateOpen = true;
      return;
    }

    final trackId = track.mediaStreamTrack.id;
    if (_vadVisualizer != null && _vadTrackId == trackId) return;

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

    // Start closed until we actually hear something above the threshold.
    _vadGateOpen = false;
    _vadHoldUntil = null;
    track.mediaStreamTrack.enabled = false;
    await visualizer.start();
  }

  void _onVadEvent(AudioVisualizerEvent e) {
    if (!_vadActive) return;
    final bands = e.event.whereType<num>().map((n) => n.toDouble());
    if (bands.isEmpty) return;
    final peak = bands.reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
    final threshold = _appCubit.state.voiceActivityThreshold;
    final now = DateTime.now();

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
  }
}
