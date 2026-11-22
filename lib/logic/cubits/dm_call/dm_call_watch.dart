part of 'dm_call_cubit.dart';

/// Everything that follows a call by the clock or by the room rather than by
/// the row: ringing and ringback, the caller giving up after thirty seconds,
/// the heartbeat, rings that outlived their doorbell, and the other person
/// dropping out of the room without hanging up.
mixin _DmCallWatchMixin on Cubit<DmCallState>, _DmCallActionsMixin {
  ServerNotificationsCubit? get _notifications;

  /// How often a device in an answered call says it is still there. The
  /// sweep ends a call nobody has vouched for in three minutes, and ends it
  /// *at* the last beat — so this is also how close a call both ends
  /// dropped out of gets its length. Once a minute recorded a short dropped
  /// call as lasting no time at all.
  static const _heartbeat = Duration(seconds: 20);

  /// How long the other person may be missing from an answered call before
  /// it is over. Counted from LiveKit taking them out of the room, which it
  /// already only does after its own reconnect window — measured at about
  /// twenty seconds for a killed client, so thirty more on top left somebody
  /// sitting in a dead call for the best part of a minute.
  static const _peerGrace = Duration(seconds: 15);

  /// How long somebody who answered has to turn up in the room at all: a
  /// phone answering from its lock screen still derives the key, fetches a
  /// token and connects. Past it they are not coming — their token was
  /// refused, or the app died on the way — and the call ends rather than
  /// sitting "in progress" for both until somebody presses Leave.
  static const _peerFirstArrival = Duration(seconds: 30);

  /// The call the other person has been seen in the room for.
  String? _peerSeenIn;

  Timer? _ringTimeout;
  Timer? _heartbeatTimer;
  Timer? _expiryTimer;
  Timer? _peerGone;

  // ── The room ──────────────────────────────────────────────

  void _onLiveKit(LiveKitState lk) {
    final active = state.active;
    final joined = _joinedCallId;
    if (active == null || joined == null) return;

    // Left from somewhere else: the call's own leave button, or a voice
    // channel picked while in it. Either way the call is over from our end.
    if (lk.dmCall?.callId != joined) {
      unawaited(hangUp());
      return;
    }
    _watchPeer(active, lk);
    _syncSounds();
  }

  bool _peerIn(ActiveDmCall active, LiveKitState lk) => lk.participants.any(
    (p) =>
        !ParticipantIdentity.isShare(p.identity) &&
        ParticipantIdentity.userIdOf(p.identity) == active.call.peerId,
  );

  /// An answered call where the other person is not in the room, for longer
  /// than a reconnect takes, is over — they closed the app, lost signal for
  /// good, or crashed, and none of those say goodbye.
  @override
  void _watchPeer(ActiveDmCall active, LiveKitState lk) {
    final connected = lk.connectionState == LiveKitConnectionState.connected;
    final here = _peerIn(active, lk);
    if (here) _peerSeenIn = active.call.id;
    if (!active.call.isLive || !connected || here) {
      _peerGone?.cancel();
      _peerGone = null;
      return;
    }
    final grace = _peerSeenIn == active.call.id
        ? _peerGrace
        : _peerFirstArrival;
    _peerGone ??= Timer(grace, () {
      _peerGone = null;
      final still = state.active;
      if (still == null || still.call.id != active.call.id) return;
      final peer = active.call.peerName;
      emit(
        state.copyWith(
          notice: Notice.info(
            'Call ended',
            _peerSeenIn == active.call.id
                ? '$peer lost their connection.'
                : '$peer couldn\'t join the call.',
          ),
        ),
      );
      unawaited(hangUp());
    });
  }

  // ── Sounds ────────────────────────────────────────────────

  /// One loop at a time: the ringtone for a call ringing us — unless we are
  /// already in a call, where it would drown out the person talking — else the
  /// ringback while our own call rings at the other end.
  @override
  void _syncSounds() {
    final loud = state.incoming.where((e) => !_mutedFor(e)).isNotEmpty;
    final lk = _livekit.state;
    final active = state.active;
    if (loud && !lk.inCall) {
      unawaited(SoundService.instance.loop(AppSound.ringtone));
    } else if (active != null &&
        active.call.isRinging &&
        !active.call.isIncomingFor(_myIdOn(active.serverId) ?? '') &&
        !_peerIn(active, lk)) {
      unawaited(SoundService.instance.loop(AppSound.ringback));
    } else {
      unawaited(SoundService.instance.stopLoop());
    }
  }

  /// A person muted to nothing still shows up calling — muting is not
  /// blocking — but does not ring out loud.
  bool _mutedFor(IncomingDmCall entry) =>
      _notifications?.state.dmLevel(entry.serverId, entry.call.peerId) ==
      NotificationLevel.none;

  String? _myIdOn(String serverId) => _server(serverId)?.user?.id;

  // ── Timers ────────────────────────────────────────────────

  @override
  void _syncTimers() {
    final active = state.active;

    final ringingOut =
        active != null &&
        active.call.isRinging &&
        !active.call.isIncomingFor(_myIdOn(active.serverId) ?? '');
    if (!ringingOut) {
      _ringTimeout?.cancel();
      _ringTimeout = null;
    } else {
      final callId = active.call.id;
      _ringTimeout ??= Timer(DmCall.ringFor, () {
        _ringTimeout = null;
        if (state.active?.call.id == callId && state.isRingingOut) {
          unawaited(_giveUpRinging(callId));
        }
      });
    }

    final live = active != null && active.call.isLive;
    if (!live) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    } else {
      _heartbeatTimer ??= Timer.periodic(_heartbeat, (_) => _beat());
    }

    if (state.incoming.isEmpty) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
    } else {
      _expiryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        final kept = DmCallLedger.expire([
          for (final e in state.incoming) e.ringing,
        ], DateTime.now());
        if (kept.length == state.incoming.length) return;
        for (final e in state.incoming) {
          if (!kept.any((k) => k.call.id == e.call.id)) {
            unawaited(NotificationService.instance.cancelCall(e.call.id));
          }
        }
        emit(
          state.copyWith(
            incoming: [
              for (final e in state.incoming)
                if (kept.any((k) => k.call.id == e.call.id)) e,
            ],
          ),
        );
        _syncSounds();
        _syncTimers();
      });
    }
  }

  Future<void> _beat() async {
    final active = state.active;
    if (active == null) return;
    final server = _server(active.serverId);
    if (server == null) return;
    final response = await _callsOn(server).dmCallAlive(active.call.id);
    // Not alive is the server saying the call is over — the doorbell that
    // said so went by unheard. Ask, and the answer ends it here too.
    if (response.success && response.data == false) _ask(active.serverId);
  }

  void _stopTimers() {
    _ringTimeout?.cancel();
    _heartbeatTimer?.cancel();
    _expiryTimer?.cancel();
    _peerGone?.cancel();
    _ringTimeout = _heartbeatTimer = _expiryTimer = _peerGone = null;
  }

  // ── Telling somebody not looking ──────────────────────────

  /// A desktop that is not in front of anybody shows the call in the system
  /// tray too. A phone does not need telling here: in the background it is
  /// the push that wakes it, and that draws its own.
  void _announceRing(IncomingDmCall entry) {
    if (!HostPlatform.isDesktop || WindowFocusService.instance.isFocused) {
      return;
    }
    if (_mutedFor(entry)) return;
    // The call's own notice, so answering, declining or the call ending
    // takes it down (`cancelCall`) and a missed call replaces it.
    unawaited(
      NotificationService.instance.showCallNotice(
        callId: entry.call.id,
        title: '${entry.call.peerName} is calling',
        body: 'Direct call · ${entry.serverName}',
        chime: false,
      ),
    );
  }

  void _announceMissed(DmCall call, String? serverName) {
    if (!HostPlatform.isDesktop) {
      // A phone in the background leaves this to the stop push. One in
      // front ignores that push, so the ring it posted earlier, Answer and
      // Decline on it, stayed in the shade: taken down here instead, by
      // somebody who watched it ring out.
      if (WindowFocusService.instance.isFocused) {
        unawaited(NotificationService.instance.cancelCall(call.id));
        if (HostPlatform.isAndroid) unawaited(WakeCalls.forgetAll([call.id]));
      }
      return;
    }
    // Back in front by now: nobody needs telling, but a ring posted while
    // the window was behind would otherwise stay up saying it is calling.
    if (WindowFocusService.instance.isFocused) {
      unawaited(NotificationService.instance.cancelCall(call.id));
      return;
    }
    unawaited(
      NotificationService.instance.showCallNotice(
        callId: call.id,
        title: 'Missed call',
        body: serverName == null
            ? 'From ${call.peerName}'
            : 'From ${call.peerName} · $serverName',
      ),
    );
  }
}
