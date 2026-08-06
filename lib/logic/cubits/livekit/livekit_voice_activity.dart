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
/// gate marks the RTP sender's encodings inactive rather than touching the
/// capture track, so the microphone is never released — see
/// [_applyGateToSender] for what the previous approach cost.
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

  final StreamController<double> _micLevelController =
      StreamController<double>.broadcast();

  /// The live microphone level, 0–1, from the analyser already running for the
  /// gate and the speaking indicator.
  ///
  /// Exposed so the mic test in settings can draw its meter without opening a
  /// second capture of a device this call is already holding. On a Bluetooth
  /// headset there is one HFP stream, and handing it back and forth is both
  /// slow and unreliable — borrowing the levels costs nothing and cannot fail.
  ///
  /// A stream rather than cubit state on purpose: this fires tens of times a
  /// second, and putting it in [LiveKitState] would rebuild every listener in
  /// the app for a number one settings widget wants.
  Stream<double> get micLevels => _micLevelController.stream;

  /// Whether [micLevels] is currently carrying anything — i.e. the call is
  /// capturing, so a meter can read it instead of opening its own microphone.
  bool get isMicLevelAvailable => _monitorActive && _vadVisualizer != null;

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
    if (_gateMechanismBroken) return false;
    // Push-to-talk already decides transmission; don't also gate.
    if (_appCubit.state.pushToTalkEnabled) return false;
    return _appCubit.state.voiceActivityThreshold > 0;
  }

  // ── Fail-open watchdog ──────────────────────────────────────────────────────
  //
  // A shut gate can only reopen itself if the analyser still hears the mic.
  // Gating at the sender is meant to guarantee that, since the capture track
  // is never touched — but that is a claim about what libwebrtc does with an
  // inactive encoding, and the previous such claim (that disabling a track
  // leaves local sinks fed) turned out to be false on Linux. It stopped
  // capture, PipeWire dropped the headset's HFP profile, the mic left the OS
  // entirely, and only changing a setting brought it back.
  //
  // So this is both the safety net and the experiment. If the analyser goes
  // quiet while the gate is shut, gating cannot work on this machine and is
  // abandoned for the rest of the run. A gate that can cost you your
  // microphone is worse than no gate.

  /// No analyser events for this long while the gate is shut means the gate
  /// cannot hear, and so cannot reopen itself.
  static const _vadWatchdog = Duration(seconds: 2);

  Timer? _vadWatchdogTimer;

  /// Set once the watchdog has had to rescue the gate. Disabling the track
  /// evidently stops capture on this machine, so gating is abandoned for the
  /// rest of the run rather than reopened to latch again two seconds later.
  bool _gateMechanismBroken = false;

  /// Restarts the countdown. Called on every analyser event, each of which is
  /// proof the mic is still being heard.
  void _armVadWatchdog() {
    _vadWatchdogTimer?.cancel();
    if (_vadGateOpen) return;
    _vadWatchdogTimer = Timer(_vadWatchdog, _onVadWatchdogExpired);
  }

  void _onVadWatchdogExpired() {
    if (_vadGateOpen) return;
    HelperMethods.printDebug(
      '[LiveKit] Voice-activity gate went deaf while shut — disabling the '
      'gate and reopening the mic for the rest of this run.',
    );
    _gateMechanismBroken = true;
    _setVadGate(true);
  }

  /// Serialises every visualizer lifecycle step.
  ///
  /// [_updateVoiceActivityMonitor] is fired from a dozen places — every mute,
  /// unmute, deafen, push-to-talk change, threshold change and connect —
  /// several of them unawaited, and it awaits twice: once tearing the old
  /// visualizer down and once starting the new one. Two overlapping runs both
  /// reach the `createVisualizer` line, and only the last one's handle is
  /// stored. The other is left *started*, attached to the mic track, with
  /// nothing holding a reference to stop it.
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
  /// can never run past a half-built visualizer.
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
      // Never leave the mic silenced by a closed gate once gating is off.
      if (track != null) track.mediaStreamTrack.enabled = true;
      _vadGateOpen = true;
      await _applyGateToSender(true);
      return;
    }

    final trackId = track.mediaStreamTrack.id;
    if (_vadVisualizer != null && _vadTrackId == trackId) {
      // Already watching this track — just reconcile the gate, since the
      // threshold or push-to-talk may have changed under us.
      if (!_gateActive) {
        _vadGateOpen = true;
        track.mediaStreamTrack.enabled = true;
        await _applyGateToSender(true);
      }
      return;
    }

    // A different (or first) mic track — rebind the visualizer to it. The mic
    // publication's track is always a LocalAudioTrack (an AudioTrack).
    await _teardownMonitor();
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
    // The capture track is always left enabled now — the gate lives on the
    // sender. Anything that disabled it earlier in this run must be undone,
    // or the analyser stays deaf.
    track.mediaStreamTrack.enabled = true;
    await visualizer.start();
    await _applyGateToSender(_vadGateOpen);
  }

  void _onVadEvent(AudioVisualizerEvent e) {
    if (!_monitorActive) return;
    final bands = e.event.whereType<num>().map((n) => n.toDouble());
    if (bands.isEmpty) return;
    final peak = bands.reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
    final now = DateTime.now();

    // Speaking indicator — independent of whether the gate is in use.
    if (_speechDetector.update(peak, now)) _syncParticipants();

    if (!_micLevelController.isClosed) _micLevelController.add(peak);

    // This event is proof the mic is still audible, whatever the gate is doing.
    _armVadWatchdog();

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
    unawaited(_applyGateToSender(open));
    // Shutting the gate starts the clock; opening it stops it.
    if (open) {
      _vadWatchdogTimer?.cancel();
      _vadWatchdogTimer = null;
    } else {
      _armVadWatchdog();
    }
  }

  /// Stops and starts transmission at the RTP sender, leaving the capture
  /// track alone.
  ///
  /// The gate used to flip `mediaStreamTrack.enabled`, which is supposed to be
  /// a cheap mute. It is not: on Linux it stops capture, which releases the
  /// microphone — the analyser goes deaf so the gate can never reopen itself,
  /// and on a Bluetooth headset every open and close renegotiates the HFP
  /// profile, which was audible as a second or two of lag on speech.
  ///
  /// Marking the encoding inactive stops the RTP instead. The device stays
  /// captured, the analyser keeps hearing, and nothing renegotiates.
  ///
  /// Failure is not fatal — it leaves the mic transmitting, which is the safe
  /// direction, and the watchdog is still watching.
  Future<void> _applyGateToSender(bool open) async {
    final sender = _localMicPublication()?.track?.sender;
    if (sender == null) return;
    try {
      final parameters = sender.parameters;
      final encodings = parameters.encodings;
      if (encodings == null || encodings.isEmpty) {
        HelperMethods.printDebug(
          '[LiveKit] Mic sender exposes no encodings — cannot gate.',
        );
        return;
      }
      for (final encoding in encodings) {
        encoding.active = open;
      }
      await sender.setParameters(parameters);
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] Could not gate the mic sender: $e');
    }
  }

  Future<void> _teardownMonitor() async {
    // Take the handles before awaiting anything. Mic changes, settings changes
    // and room teardown all reach here, and a second caller that arrives mid-
    // await would otherwise stop and dispose the same visualizer again.
    final listener = _vadListener;
    final visualizer = _vadVisualizer;
    _vadListener = null;
    _vadVisualizer = null;
    _vadTrackId = null;
    _vadHoldUntil = null;
    // No analyser means no events, and a countdown with nothing to reset it
    // would fire on a gate that is already being taken down.
    _vadWatchdogTimer?.cancel();
    _vadWatchdogTimer = null;

    await listener?.dispose();
    await visualizer?.stop();
    await visualizer?.dispose();
    // A muted mic must not leave the glow stuck on.
    if (_speechDetector.reset()) _syncParticipants();
  }
}
