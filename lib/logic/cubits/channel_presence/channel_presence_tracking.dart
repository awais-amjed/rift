part of 'channel_presence_cubit.dart';

/// Keeping our own presence entry on the server, and noticing when it isn't.
///
/// Realtime allows one client **5 presence events per 30 seconds**
/// (`CLIENT_PRESENCE_MAX_CALLS` / `CLIENT_PRESENCE_WINDOW_MS`, realtime v2.102
/// defaults; the tenant columns `max_client_presence_events_per_window` and
/// `client_presence_window_ms` override them). The sixth is not refused — it
/// logs `ClientPresenceRateLimitReached` and **terminates the channel**
/// (`shutdown_response` → `{:stop, :normal}`), and the client is barely told:
/// its own copy of the state still lists it, so it looks online to itself while
/// for everyone else it has left, and every later track times out against a
/// process that no longer exists.
///
/// Since the split, the entry says only `{userId, displayName}` and is
/// published once per connection, which is nowhere near that limit. The
/// rationing stays anyway — it costs a timer, and it is what stops anyone
/// quietly putting a changing value back into this payload.
mixin _PresenceTrackingMixin on Cubit<ChannelPresenceState> {
  ServerCubit get _serverCubit;
  RealtimeChannel? get _channel;
  bool get _subscribed;

  /// Leaves the presence topic and joins it again — the only cure for a
  /// dropped entry, since the ration and the channel process both belong to
  /// the join, not to the socket it rides on.
  Future<void> _rebuild();

  /// Whether our entry is on the server, as far as we know. Only ever a belief;
  /// see [_publishPending] and [_healTracking] for what happens when it's wrong.
  bool _tracked = false;

  /// The queued publish, and when the recent ones went out.
  Timer? _publishTimer;
  final List<DateTime> _recentPublishes = [];
  bool _hasPending = false;
  bool _publishing = false;

  Timer? _rebuildTimer;
  int _rebuildAttempt = 0;

  /// A fresh connection: a new ration, and nothing published on it yet.
  void _startTrackingSession() {
    _tracked = false;
    _recentPublishes.clear();
    _cancelPending();
  }

  /// The connection is going away, and anything in flight went with it.
  void _stopTracking() {
    _tracked = false;
    _cancelPending();
    _publishing = false;
  }

  /// Publishes our presence entry if the server hasn't got one.
  void _ensureTracked() {
    if (isClosed || _hasPending || _tracked) return;
    if (_channel == null || !_subscribed) return;
    if (_serverCubit.state.selectedServer?.user == null) return;
    _hasPending = true;
    _publishTimer?.cancel();
    _publishTimer = Timer(
      PresenceRation.publishWait(recent: _recentPublishes, now: DateTime.now()),
      () => unawaited(_publishPending()),
    );
  }

  /// Our entry has gone missing from the state the server is broadcasting to
  /// everyone, while we still believe we published one.
  void _healTracking(Set<String> online) {
    if (!PresenceRation.shouldRetrack(
      tracked: _tracked,
      localUserId: _serverCubit.state.selectedServer?.user?.id,
      onlineUserIds: online,
    )) {
      return;
    }
    _tracked = false;
    _ensureTracked();
  }

  void _cancelPending() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _hasPending = false;
  }

  Future<void> _publishPending() async {
    if (isClosed || !_hasPending || _channel == null || _publishing) return;
    final user = _serverCubit.state.selectedServer?.user;
    if (user == null) return;

    _publishing = true;
    // Spend it before the await: anything arriving mid-flight must see this
    // one already counted, or the two together break the ration.
    final spent = PresenceRation.spend(_recentPublishes, DateTime.now());
    _recentPublishes
      ..clear()
      ..addAll(spent);
    _hasPending = false;

    ChannelResponse? result;
    try {
      // Location is deliberately absent — it lives on the broadcast topic.
      result = await _channel?.track({
        'userId': user.id,
        'displayName': user.displayName,
      });
    } catch (_) {}
    _publishing = false;
    if (isClosed) return;

    if (result == ChannelResponse.ok) {
      _tracked = true;
      _rebuildAttempt = 0;
      return;
    }

    // Refused, timed out, or sent while the socket was down. In every one of
    // those cases the entry isn't there, and tracking again on this channel
    // won't put it there.
    _tracked = false;
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    if (isClosed || _rebuildTimer != null) return;
    final delay = PresenceRation.rebuildDelay(_rebuildAttempt);
    _rebuildAttempt++;
    _rebuildTimer = Timer(delay, () {
      _rebuildTimer = null;
      unawaited(_rebuild());
    });
  }
}
