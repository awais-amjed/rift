part of 'server_notifications_cubit.dart';

/// One authenticated Realtime + REST connection per joined server, and the
/// bookkeeping that keeps the set of them matching the server list.
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
        // Token rotated (silent re-auth) → re-point both transports and re-seed.
        existing.token = server.token;
        _authClient(existing.client, server.supabaseKey!, server.token);
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
    final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _authClient(client, server.supabaseKey!, server.token);
    final channel = client.channel('unread:${server.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) => _onChannelMessage(server.id, payload.newRecord),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'dm_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_id',
          value: server.user!.id,
        ),
        callback: (payload) => _onDmMessage(server.id, payload.newRecord),
      )
      ..subscribe();
    _subs[server.id] = _ServerSub(
      client: client,
      channel: channel,
      token: server.token,
      userId: server.user!.id,
    );
    unawaited(_seed(server.id));
  }

  /// Point both REST and Realtime at the user's JWT so RLS sees `auth.uid()`.
  void _authClient(SupabaseClient client, String anonKey, String token) {
    client.headers = {'apikey': anonKey, 'Authorization': 'Bearer $token'};
    client.realtime.setAuth(token);
  }

  void _teardownServer(String serverId) {
    final sub = _subs.remove(serverId);
    if (sub == null) return;
    _forgetPeerNames(serverId);
    if (!isClosed) emit(state.clearedServer(serverId));
    unawaited(() async {
      try {
        await sub.channel.unsubscribe();
        sub.client.removeAllChannels();
        await sub.client.dispose();
      } catch (_) {}
    }());
  }
}

/// A single server's authenticated connection.
class _ServerSub {
  final SupabaseClient client;
  final RealtimeChannel channel;
  final String userId;
  String token;

  _ServerSub({
    required this.client,
    required this.channel,
    required this.userId,
    required this.token,
  });
}
