part of 'dm_call_cubit.dart';

/// Everything that follows a call by the clock or by the room rather than by
/// the row: ringing and ringback, the caller giving up after thirty seconds,
/// the heartbeat, rings that outlived their doorbell, and the other person
/// dropping out of the room without hanging up.
mixin _DmCallWatchMixin on Cubit<DmCallState>, _DmCallActionsMixin {
  ServerNotificationsCubit? get _notifications;

  /// How long a caller lets it ring. The server's window is longer (45 s) so
  /// that an answer in flight at the last moment still lands.
  static const _ringFor = Duration(seconds: 30);

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
  void _watchPeer(ActiveDmCall active, LiveKitState lk) {
    final connected = lk.connectionState == LiveKitConnectionState.connected;
    if (!active.call.isLive || !connected || _peerIn(active, lk)) {
      _peerGone?.cancel();
      _peerGone = null;
      return;
    }
    _peerGone ??= Timer(_peerGrace, () {
      _peerGone = null;
      final still = state.active;
      if (still == null || still.call.id != active.call.id) return;
      HelperMethods.showToast(
        title: 'Call ended',
        description: '${active.call.peerName} lost their connection.',
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
      _ringTimeout ??= Timer(_ringFor, () {
        _ringTimeout = null;
        if (state.active?.call.id == callId && state.isRingingOut) {
          unawaited(hangUp());
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
          for (final e in state.incoming) (serverId: e.serverId, call: e.call),
        ], DateTime.now());
        if (kept.length == state.incoming.length) return;
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
    final response = await _serverCubit.dmCallAlive(server, active.call.id);
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
    unawaited(
      NotificationService.instance.showMessage(
        title: '${entry.call.peerName} is calling',
        body: 'Direct call · ${entry.serverName}',
        chime: false,
      ),
    );
  }

  void _announceMissed(DmCall call, String? serverName) {
    if (!HostPlatform.isDesktop || WindowFocusService.instance.isFocused) {
      return;
    }
    unawaited(
      NotificationService.instance.showMessage(
        title: 'Missed call',
        body: serverName == null
            ? 'From ${call.peerName}'
            : 'From ${call.peerName} · $serverName',
      ),
    );
  }
}
