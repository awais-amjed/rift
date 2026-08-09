import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/server.dart';
import '../../services/presence_ration.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

part 'channel_presence_state.dart';

/// Maintains Supabase Realtime Presence for the selected server.
///
/// The local user is tracked for as long as the server is selected, so
/// presence answers both questions the UI asks: *who is online here* (the
/// member sidebar) and *who is in which voice channel* (the channel list). The
/// tracked `channelId` is null while not in voice, and follows the LiveKit
/// connection otherwise — no changes needed in LiveKitCubit.
///
/// ## Presence updates are rationed, and overspending kills the channel
///
/// Realtime allows one client **5 presence events per 30 seconds**
/// (`CLIENT_PRESENCE_MAX_CALLS` / `CLIENT_PRESENCE_WINDOW_MS`, defaults in
/// realtime v2.102). The sixth is not refused — it logs
/// `ClientPresenceRateLimitReached` and **terminates the channel**
/// (`shutdown_response` → `{:stop, :normal}`).
///
/// The client is barely told. Its own copy of the presence state still lists
/// it, so it looks online to itself, while for everyone else it has left. Every
/// later track goes to a channel process that no longer exists and times out.
/// Moving someone used to cost two updates (leaving, then arriving), so three
/// moves in half a minute made a member invisible until they restarted the app.
///
/// Three rules come out of that, and all three are load-bearing:
///
/// * **Stay inside the ration.** [PresenceRation.publishWait] holds an update
///   back until there is room in the 30-second window, and bursts coalesce into
///   the last value — only where we are *now* is worth spending an event on.
/// * **Don't spend two events on one move.** The half-second of "nowhere"
///   between leaving one channel and joining the next is never published.
/// * **A channel that stops working is rebuilt, not retried.** The ration and
///   the channel process both belong to the connection, so a new one starts
///   clean; tracking again on the old one can never work.
class ChannelPresenceCubit extends Cubit<ChannelPresenceState> {
  final ServerCubit _serverCubit;
  final LiveKitCubit _livekitCubit;

  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<LiveKitState>? _lkSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _currentServerId;
  bool _subscribed = false;

  /// Whether the local user is tracked at all, and the channel id in that
  /// entry (null while not in a voice channel). Both are needed: "tracked with
  /// no channel" and "not tracked" are different states, and collapsing them
  /// would re-track on every LiveKit event. Only ever our *belief* about what
  /// the server holds — see [_publishPending] for what happens when it's wrong.
  bool _tracked = false;
  String? _trackedChannelId;

  /// The update waiting to go out, and when the recent ones went. `_hasPending`
  /// is separate because "publish null" and "nothing to publish" are different.
  Timer? _publishTimer;
  final List<DateTime> _recentPublishes = [];
  bool _hasPending = false;
  String? _pendingChannelId;

  /// One update in flight at a time. Two overlapping tracks can be applied by
  /// the server in either order, and the loser is a member shown in the channel
  /// they left — the exact thing this class exists to get right.
  bool _publishing = false;

  Timer? _rebuildTimer;
  int _rebuildAttempt = 0;

  /// Set while we're taking the channel down on purpose, so the `closed` status
  /// that follows isn't mistaken for the server hanging up on us.
  bool _tearingDown = false;

  ChannelPresenceCubit({
    required ServerCubit serverCubit,
    required LiveKitCubit livekitCubit,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       super(const ChannelPresenceState()) {
    _serverSub = serverCubit.stream.listen(_onServerChanged);
    _lkSub = livekitCubit.stream.listen((_) => _reconcileTracking());
    // Bootstrap with current state
    _onServerChanged(serverCubit.state);
  }

  // ── Server changes ───────────────────────────────────────────────────────

  Future<void> _onServerChanged(ServerState serverState) async {
    final server = serverState.selectedServer;
    if (server?.id == _currentServerId) return;
    await _disconnectPresence();
    if (server != null && server.supabaseKey != null) {
      _connectPresence(server);
    }
  }

  void _connectPresence(Server server) {
    _currentServerId = server.id;
    _tracked = false;
    _trackedChannelId = null;
    _subscribed = false;
    // A new connection carries a new ration, so nothing spent on the old one
    // should hold the first update back.
    _recentPublishes.clear();
    _client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _channel = _client!.channel('presence:${server.id}');

    _channel!
        .onPresenceSync((_) => _syncPresence())
        .onPresenceJoin((_) => _syncPresence())
        .onPresenceLeave((_) => _syncPresence())
        .subscribe((status, [err]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            // (Re)subscribed — re-establish our presence from scratch (a
            // realtime reconnect drops the server-side entry, and rejoining
            // does not bring it back on its own).
            _subscribed = true;
            _rebuildAttempt = 0;
            _tracked = false;
            _trackedChannelId = null;
            _reconcileTracking();
          } else {
            _subscribed = false;
            // Closed, errored or timed out. Overspending the presence ration
            // ends the channel this way, and nothing rejoins it on its own —
            // this is the only notice we get that we've gone quiet.
            if (!_tearingDown) _scheduleRebuild();
          }
        });
  }

  /// Tears the presence channel down. [keepState] holds on to what we last
  /// knew during a rebuild, so the sidebar doesn't blink empty on the way
  /// through.
  Future<void> _disconnectPresence({bool keepState = false}) async {
    _tearingDown = true;
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    _currentServerId = null;
    _tracked = false;
    _trackedChannelId = null;
    _subscribed = false;
    _publishTimer?.cancel();
    _publishTimer = null;
    _hasPending = false;
    // Whatever was in flight belongs to a channel that no longer exists.
    _publishing = false;
    try {
      await channel?.untrack();
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
    _tearingDown = false;
    if (!isClosed && !keepState) emit(const ChannelPresenceState());
  }

  // ── LiveKit state → track / untrack ─────────────────────────────────────

  /// Brings the tracked presence in line with the live LiveKit state. We stay
  /// tracked the whole time the server is selected (that *is* being online);
  /// only the `channelId` in the entry follows the voice connection.
  void _reconcileTracking() {
    if (_channel == null || !_subscribed) return;

    final user = _serverCubit.state.selectedServer?.user;
    if (user == null) return;

    final lkState = _livekitCubit.state;
    // Connecting is not "nowhere". A move goes connected → connecting →
    // connected, and announcing the gap would spend a second presence update
    // to describe half a second of travel. Genuinely leaving a call goes
    // straight to disconnected, which does publish.
    if (lkState.connectionState == LiveKitConnectionState.connecting) return;

    final channelId =
        lkState.connectionState == LiveKitConnectionState.connected
        ? lkState.currentChannelId
        : null;

    if (_tracked && channelId == _trackedChannelId) {
      // The server already says where we are — and anything queued behind that
      // is now describing a channel we've come back from. Leaving it armed
      // announces the old channel a few seconds after we returned, and spends
      // an event of the ration to be wrong.
      _cancelPending();
      return;
    }
    _publish(channelId);
  }

  /// Queues [channelId] to be published as soon as the ration allows. A newer
  /// value replaces whatever was waiting: only where we are *now* is worth
  /// spending an event on.
  void _publish(String? channelId) {
    if (isClosed) return;
    _pendingChannelId = channelId;
    _hasPending = true;
    _publishTimer?.cancel();
    _publishTimer = Timer(
      PresenceRation.publishWait(recent: _recentPublishes, now: DateTime.now()),
      () => unawaited(_publishPending()),
    );
  }

  void _cancelPending() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _hasPending = false;
  }

  Future<void> _publishPending() async {
    if (isClosed || !_hasPending || _channel == null) return;
    // Someone else is mid-flight; they'll come back for whatever is pending.
    if (_publishing) return;
    final user = _serverCubit.state.selectedServer?.user;
    if (user == null) return;

    _publishing = true;
    // Spend it before the await: a second change arriving mid-flight must see
    // this one already counted, or the two together break the ration.
    final spent = PresenceRation.spend(_recentPublishes, DateTime.now());
    _recentPublishes
      ..clear()
      ..addAll(spent);

    final channelId = _pendingChannelId;
    _hasPending = false;

    ChannelResponse? result;
    try {
      result = await _channel?.track({
        // Absent while not in a voice channel — the entry still means online.
        'channelId': ?channelId,
        'userId': user.id,
        'displayName': user.displayName,
      });
    } catch (_) {}
    _publishing = false;
    if (isClosed) return;

    if (result == ChannelResponse.ok) {
      _tracked = true;
      _trackedChannelId = channelId;
      _rebuildAttempt = 0;
      // Where we are may have moved on while this was in flight. Re-derive it
      // from the live state rather than trusting what was queued — that is
      // what makes every path here converge on the truth.
      _reconcileTracking();
      return;
    }

    // Refused, timed out, or sent while the socket was down. In every one of
    // those cases the entry isn't there and tracking again on this channel
    // won't put it there.
    _tracked = false;
    _trackedChannelId = null;
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

  /// Throws the presence channel away and builds another.
  ///
  /// The only cure for a dropped entry: the allowance is per connection, so a
  /// new socket can track again where the old one silently could not.
  Future<void> _rebuild() async {
    if (isClosed) return;
    final server = _serverCubit.state.selectedServer;
    if (server == null || server.supabaseKey == null) return;

    await _disconnectPresence(keepState: true);
    if (isClosed) return;
    _connectPresence(server);
  }

  void _syncPresence() {
    if (isClosed) return;
    final entries = _channel?.presenceState() ?? <SinglePresenceState>[];

    final localUserId = _serverCubit.state.selectedServer?.user?.id;

    final Map<String, List<PresenceUser>> result = {};
    final Set<String> online = {};
    for (final entry in entries) {
      for (final presence in entry.presences) {
        final payload = presence.payload;
        final channelId = payload['channelId'] as String?;
        final userId = payload['userId'] as String?;
        final displayName = payload['displayName'] as String?;
        if (userId == null || displayName == null) continue;

        // Online counts the local user — the sidebar lists you too.
        online.add(userId);

        // ...but the per-channel roster doesn't: the local user's own channel
        // is rendered from live LiveKit participants, so a stale self-entry
        // (before an untrack round-trips) can't show us where we no longer are.
        if (channelId == null || userId == localUserId) continue;
        result
            .putIfAbsent(channelId, () => [])
            .add(PresenceUser(userId: userId, displayName: displayName));
      }
    }

    emit(ChannelPresenceState(channelPresence: result, onlineUserIds: online));

    if (PresenceRation.shouldRetrack(
      tracked: _tracked,
      localUserId: localUserId,
      onlineUserIds: online,
    )) {
      // Re-derive where we are rather than re-sending what we last said: the
      // belief that just proved wrong is no basis for the next update.
      _tracked = false;
      _reconcileTracking();
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _lkSub?.cancel();
    _rebuildTimer?.cancel();
    await _disconnectPresence();
    return super.close();
  }
}
