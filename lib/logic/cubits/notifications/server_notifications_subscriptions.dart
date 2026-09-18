part of 'server_notifications_cubit.dart';

/// One unread subscription per joined server, on that server's shared
/// connection, and the bookkeeping that keeps the set matching the server list.
mixin _SubscriptionsMixin on Cubit<NotificationsState>, _PeerNamesMixin {
  ServerCubit get _serverCubit;

  /// Per-server live subscription + authenticated client, keyed by server id.
  @override
  Map<String, _ServerSub> get _subs;

  Future<void> _seed(String serverId);
  void _onChannelMessage(String serverId, Map<String, dynamic> row);
  void _onDmMessage(String serverId, Map<String, dynamic> row);

  void _sync() {
    final servers = _serverCubit.state.servers;
    final joined = <String>{};

    for (final server in servers) {
      if (server.supabaseKey == null ||
          server.user == null ||
          server.token.isEmpty) {
        continue;
      }
      joined.add(server.id);

      // Keep the JWT fresh (coalesced; no-op if already fresh/refreshing).
      final nearExpiry = server.isTokenNearExpiry;
      if (nearExpiry) {
        unawaited(_serverCubit.reAuthenticateServer(server.id));
      }

      final existing = _subs[server.id];
      if (existing == null) {
        // Don't open a subscription with a stale/expired JWT (hydrated tokens
        // read as near-expiry on startup) — wait for the refresh above to land
        // a fresh token, which re-triggers _sync and subscribes then.
        if (!nearExpiry) _subscribe(server);
      } else if (existing.token != server.token) {
        // Token rotated (silent re-auth). The shared connection has already
        // moved to it; what's left is to re-read what the old one missed.
        existing.token = server.token;
        unawaited(_seed(server.id));
      }
    }

    // Tear down subscriptions for servers we've left.
    for (final id in _subs.keys.toList()) {
      if (!joined.contains(id)) _teardownServer(id);
    }
  }

  /// Watch the message tables themselves.
  ///
  /// There used to be a `notifications` table here — one row fanned out per
  /// recipient per message, existing only so a client had something it was
  /// allowed to subscribe to. With policies on `messages` and `dm_messages`,
  /// Realtime re-checks them per subscriber and delivers only rows this member
  /// could have selected, so the fanout (and its retention job) is gone.
  ///
  /// DMs are filtered to those addressed to us; channel messages can't be
  /// filtered that way and don't need to be — RLS already limits them to this
  /// server, and our own messages are skipped on arrival.
  void _subscribe(Server server) {
    final realtime = _serverCubit.realtime;
    final userId = server.user!.id;
    final client = realtime.clientFor(server);
    final topic = realtime.join(
      server,
      'unread:${server.id}',
      setUp: (channel, dispatch) => _bindUnread(channel, dispatch, userId),
    );
    if (client == null || topic == null) return;
    topic
      ..on('message', (row) => _onChannelMessage(server.id, row))
      ..on('dm', (row) => _onDmMessage(server.id, row))
      ..on('prefs', (_) => unawaited(_seed(server.id)));
    _subs[server.id] = _ServerSub(
      client: client,
      topic: topic,
      token: server.token,
      userId: userId,
    );
    unawaited(_seed(server.id));
  }

  void _bindUnread(
    RealtimeChannel channel,
    RealtimeDispatch dispatch,
    String userId,
  ) {
    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) => dispatch('message', payload.newRecord),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'dm_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_id',
          value: userId,
        ),
        callback: (payload) => dispatch('dm', payload.newRecord),
      )
      // A level changed somewhere else — the phone, another desktop. Without
      // this the setting is per-device in everything but storage: written to
      // the server, read at sign-in, and never looked at again, so the window
      // you left open goes on notifying you about a channel you muted an hour
      // ago. Every event re-seeds rather than being applied on its own,
      // because the answer is a chain across three scopes and a re-seed is one
      // round trip that already returns all of it.
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notification_prefs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) => dispatch('prefs', const {}),
      );
  }

  void _teardownServer(String serverId) {
    final sub = _subs.remove(serverId);
    if (sub == null) return;
    _forgetPeerNames(serverId);
    if (!isClosed) emit(state.clearedServer(serverId));
    unawaited(sub.topic.release());
  }
}

/// A single server's unread subscription, and the shared client its REST
/// calls go out on.
class _ServerSub {
  final SupabaseClient client;
  final RealtimeLease topic;
  final String userId;
  String token;

  _ServerSub({
    required this.client,
    required this.topic,
    required this.userId,
    required this.token,
  });
}
