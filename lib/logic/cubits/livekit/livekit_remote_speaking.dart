part of 'livekit_cubit.dart';

/// Speaking detection for *remote* participants, measured locally.
///
/// LiveKit's `isSpeaking` comes from the SFU's active-speaker detection, which
/// reports only the loudest few participants on a fixed interval and above a
/// deliberately conservative level. Normal-volume speech frequently never lit
/// the indicator — the same problem already fixed for the local user.
///
/// The server-side knobs (`audio.active_level`, `update_interval` in
/// livekit.yaml) would help, but they're the wrong lever for Rift: every
/// self-hosted server runs its own LiveKit, `--dev` mode ignores a config file
/// unless one is passed, and the result would vary per deployment. Measuring
/// each subscribed audio track here gives every participant the *same*
/// threshold as the local user, on any LiveKit.
///
/// One visualizer per subscribed microphone track. Screenshare audio is
/// skipped — a shared desktop's audio isn't someone speaking.
mixin _RemoteSpeakingMixin on Cubit<LiveKitState> {
  void _syncParticipants();

  final Map<String, AudioVisualizer> _remoteVisualizers = {};
  final Map<String, EventsListener<AudioVisualizerEvent>> _remoteListeners = {};
  final Map<String, SpeechDetector> _remoteDetectors = {};

  /// Whether [identity] is speaking, by our own measurement. Null when we have
  /// no detector for them (not subscribed yet), so callers can fall back to the
  /// server's view rather than claiming silence.
  bool? remoteSpeaking(String identity) =>
      _remoteDetectors[identity]?.isSpeaking;

  /// Attach a level monitor to a newly subscribed remote microphone track.
  /// Public because a sibling mixin calls it — a private member implemented in
  /// one mixin and declared in another trips `unused_element` (CODE_STYLE §5).
  /// Cubit-internal; not part of the public API.
  void watchRemoteAudio(RemoteParticipant participant, Track? track) {
    if (track is! RemoteAudioTrack) return;
    final identity = participant.identity;
    // A screenshare's audio is the shared app, not a voice.
    if (ParticipantIdentity.isScreenshare(identity)) return;
    if (_remoteVisualizers.containsKey(identity)) return;

    try {
      final visualizer = createVisualizer(
        track,
        options: const AudioVisualizerOptions(
          barCount: 7,
          centeredBands: false,
        ),
      );
      _remoteVisualizers[identity] = visualizer;
      _remoteDetectors[identity] = SpeechDetector();
      _remoteListeners[identity] = visualizer.createListener()
        ..on<AudioVisualizerEvent>((e) => _onRemoteLevel(identity, e));
      unawaited(visualizer.start());
    } catch (e) {
      debugPrint('remote speaking monitor failed for $identity: $e');
      unwatchRemoteAudio(identity);
    }
  }

  void _onRemoteLevel(String identity, AudioVisualizerEvent e) {
    final detector = _remoteDetectors[identity];
    if (detector == null) return;
    final bands = e.event.whereType<num>().map((n) => n.toDouble());
    if (bands.isEmpty) return;
    final peak = bands.reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
    if (detector.update(peak, DateTime.now())) _syncParticipants();
  }

  /// Drop the monitor for one participant — unsubscribed, muted, or gone.
  /// Cubit-internal, public for the same reason as [watchRemoteAudio].
  void unwatchRemoteAudio(String identity) {
    final listener = _remoteListeners.remove(identity);
    final visualizer = _remoteVisualizers.remove(identity);
    final hadSpeech = _remoteDetectors.remove(identity)?.isSpeaking ?? false;
    unawaited(_disposeMonitor(listener, visualizer));
    // A participant who leaves mid-word must not stay lit.
    if (hadSpeech && !isClosed) _syncParticipants();
  }

  Future<void> _disposeMonitor(
    EventsListener<AudioVisualizerEvent>? listener,
    AudioVisualizer? visualizer,
  ) async {
    try {
      await listener?.dispose();
      await visualizer?.stop();
      await visualizer?.dispose();
    } catch (_) {}
  }

  /// Tear down every remote monitor — on disconnect or cubit close.
  /// Cubit-internal, public for the same reason as [watchRemoteAudio].
  Future<void> stopRemoteSpeakingMonitors() async {
    final listeners = _remoteListeners.values.toList();
    final visualizers = _remoteVisualizers.values.toList();
    _remoteListeners.clear();
    _remoteVisualizers.clear();
    _remoteDetectors.clear();
    for (var i = 0; i < visualizers.length; i++) {
      await _disposeMonitor(
        i < listeners.length ? listeners[i] : null,
        visualizers[i],
      );
    }
  }
}
