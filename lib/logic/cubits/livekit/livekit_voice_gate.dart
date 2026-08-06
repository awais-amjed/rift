part of 'livekit_cubit.dart';

/// The noise gate: decides, from the local microphone level, whether the mic
/// should be transmitting at all.
///
/// Split from [_VoiceActivityMixin] so that the question "is the user above
/// their threshold right now" stays separate from the plumbing that measures
/// the level. The monitor feeds this one number per frame through [_feedGate]
/// and otherwise knows nothing about how transmission is stopped.
///
/// Gating happens at the RTP sender rather than on the capture track — see
/// [_applyGateToSender] for what the alternatives cost.
mixin _VoiceGateMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;

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

  // Everything below is called from [_VoiceActivityMixin], which reaches it
  // through an abstract declaration of its own rather than through this body —
  // a hop the unused-element check can't follow across two mixins.

  /// Feeds one measured level. The monitor calls this for every audio frame.
  // ignore: unused_element
  void _feedGate(double level, DateTime now) {
    if (!_gateActive) return;
    final threshold = _appCubit.state.voiceActivityThreshold;
    if (level >= threshold) {
      _vadHoldUntil = now.add(_vadHold);
      _setVadGate(true, level);
    } else if (_vadHoldUntil == null || now.isAfter(_vadHoldUntil!)) {
      _setVadGate(false, level);
    }
  }

  /// Sets the gate up for a freshly bound microphone track: shut if gating is
  /// on, so nothing is transmitted until something is actually heard.
  // ignore: unused_element
  Future<void> _primeGate() async {
    _vadGateOpen = !_gateActive;
    _vadHoldUntil = null;
    _gateDiagnosticsLogged = false;
    _cancelVadWatchdog();
    await _applyGateToSender(_vadGateOpen);
    _armVadWatchdog();
  }

  /// Unconditionally returns the mic to transmitting — gating was turned off,
  /// the mic went away, or the call ended. Never leave a mic silenced by a gate
  /// that is no longer running.
  // ignore: unused_element
  Future<void> _releaseGate() async {
    _vadGateOpen = true;
    _vadHoldUntil = null;
    _cancelVadWatchdog();
    await _applyGateToSender(true);
  }

  void _setVadGate(bool open, [double? level]) {
    if (_vadGateOpen == open) return;
    _vadGateOpen = open;
    HelperMethods.printDebug(
      '[LiveKit] Voice gate ${open ? 'open' : 'shut'}'
      '${level == null ? '' : ' at level ${level.toStringAsFixed(3)}'} '
      '(threshold ${_appCubit.state.voiceActivityThreshold.toStringAsFixed(3)})',
    );
    unawaited(_applyGateToSender(open));
    // Shutting the gate starts the clock; opening it stops it.
    if (open) {
      _vadWatchdogTimer?.cancel();
      _vadWatchdogTimer = null;
    } else {
      _armVadWatchdog();
    }
  }

  /// Set once per track, so the encoding read-back below is logged on the
  /// first gate application rather than on every one.
  bool _gateDiagnosticsLogged = false;

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
  /// captured, the analyser keeps hearing, and nothing renegotiates. Whether
  /// libwebrtc honours that on a published audio sender is exactly what is in
  /// doubt, which is why the first application of each track reads the
  /// parameters back and logs what actually stuck.
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
      if (!_gateDiagnosticsLogged) {
        _gateDiagnosticsLogged = true;
        final readBack = sender.parameters.encodings
            ?.map((e) => e.active)
            .toList();
        HelperMethods.printDebug(
          '[LiveKit] Gate wrote active=$open to ${encodings.length} '
          'encoding(s); reading back gives $readBack',
        );
      }
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] Could not gate the mic sender: $e');
    }
  }

  // ── Fail-open watchdog ──────────────────────────────────────────────────────
  //
  // A shut gate can only reopen itself if the monitor still hears the mic.
  // Gating at the sender is meant to guarantee that, since the capture track
  // is never touched — but that is a claim about what libwebrtc does with an
  // inactive encoding, and the previous such claim (that disabling a track
  // leaves local sinks fed) turned out to be false on Linux. It stopped
  // capture, PipeWire dropped the headset's HFP profile, the mic left the OS
  // entirely, and only changing a setting brought it back.
  //
  // So this is both the safety net and the experiment. If the monitor goes
  // quiet while the gate is shut, gating cannot work on this machine and is
  // abandoned for the rest of the run. A gate that can cost you your
  // microphone is worse than no gate.

  /// No audio frames for this long while the gate is shut means the gate
  /// cannot hear, and so cannot reopen itself.
  static const _vadWatchdog = Duration(seconds: 2);

  Timer? _vadWatchdogTimer;

  /// When the monitor last heard the microphone.
  ///
  /// A timestamp rather than a timer the monitor resets: frames arrive every
  /// 10 ms, and re-arming a [Timer] a hundred times a second to express "still
  /// alive" is a lot of allocation for a check that runs twice a second.
  DateTime? _lastMicFrameAt;

  /// Set once the watchdog has had to rescue the gate. Gating evidently stops
  /// capture on this machine, so it is abandoned for the rest of the run
  /// rather than reopened to latch again two seconds later.
  bool _gateMechanismBroken = false;

  /// Records that the mic was heard. Called for every audio frame.
  // ignore: unused_element
  void _noteMicFrame(DateTime now) => _lastMicFrameAt = now;

  /// Starts the countdown, if the gate is shut and one isn't already running.
  void _armVadWatchdog() {
    if (_vadGateOpen || _vadWatchdogTimer != null) return;
    _vadWatchdogTimer = Timer(_vadWatchdog, _onVadWatchdogExpired);
  }

  void _onVadWatchdogExpired() {
    _vadWatchdogTimer = null;
    if (_vadGateOpen) return;

    final lastFrame = _lastMicFrameAt;
    if (lastFrame != null &&
        DateTime.now().difference(lastFrame) < _vadWatchdog) {
      // Still being heard — keep watching.
      _armVadWatchdog();
      return;
    }

    HelperMethods.printDebug(
      '[LiveKit] Voice-activity gate went deaf while shut — disabling the '
      'gate and reopening the mic for the rest of this run.',
    );
    _gateMechanismBroken = true;
    _setVadGate(true);
  }

  /// Stops the watchdog. The monitor calls this while tearing down, where a
  /// countdown with nothing left to reset it would fire on a gate that is
  /// already going away.
  // ignore: unused_element
  void _cancelVadWatchdog() {
    _vadWatchdogTimer?.cancel();
    _vadWatchdogTimer = null;
    _lastMicFrameAt = null;
  }
}
