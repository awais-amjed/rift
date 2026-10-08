part of 'server_notifications_cubit.dart';

/// One unread subscription per joined server, on that server's shared
/// connection, and the bookkeeping that keeps the set matching the server list.
mixin _SubscriptionsMixin on Cubit<NotificationsState>, _PeerNamesMixin {
  ServerCubit get _serverCubit;
  SessionRepository get _session;

  /// Per-server live subscription + authenticated client, keyed by server id.
  @override
  Map<String, _ServerSub> get _subs;

  Future<void> _seed(String serverId);
  void _onChannelMessage(String serverId, Map<String, dynamic> row);
  void _onDmMessage(String serverId, Map<String, dynamic> row);
  void _onChannelMessageChanged(String serverId, Map<String, dynamic> row);
  void _onDmMessageChanged(String serverId);

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
      // Every pass, not just the first: private channels come and go, and so
      // does the caller's seat at them. `_sync` runs on every change to the
      // server list, and a channel appearing or disappearing is one.
      _syncPrivateChannels(server);
    }

    // Tear down subscriptions for servers we've left.
    for (final id in _subs.keys.toList()) {
      if (!joined.contains(id)) _teardownServer(id);
    }
  }

  /// Hear new messages as the database announces them: on the
  /// server's topic for open channels, and on our own for private channels,
  /// ephemeral replies, DMs and a notification level set on another device.
  ///
  /// There used to be a `notifications` table here, one row fanned out per
  /// recipient per message; then every member watching `messages` itself, with
  /// Realtime re-checking the read policy for each of them on each row. Now the
  /// database says it once, to the topic that may hear it, and says only ids —
  /// the badge needs which channel and who from, never what was said.
  void _subscribe(Server server) {
    final realtime = _session.realtime;
    final userId = server.user!.id;
    final client = realtime.clientFor(server);
    final shared = realtime.join(server, ServerTopics.server(server.id));
    final own = realtime.join(server, ServerTopics.user(userId));
    if (client == null || shared == null || own == null) {
      unawaited(shared?.release());
      unawaited(own?.release());
      return;
    }
    void onMessage(RealtimePayload message) =>
        _onChannelMessage(server.id, BroadcastPayload.of(message));
    void onChanged(RealtimePayload message) =>
        _onChannelMessageChanged(server.id, BroadcastPayload.of(message));
    shared
      ..onBroadcast(ServerEvent.message, onMessage)
      ..onBroadcast(ServerEvent.messageChanged, onChanged);
    own
      ..onBroadcast(ServerEvent.message, onMessage)
      ..onBroadcast(ServerEvent.messageChanged, onChanged)
      ..onBroadcast(
        ServerEvent.dm,
        (message) => _onDmMessage(server.id, BroadcastPayload.of(message)),
      )
      ..onBroadcast(
        ServerEvent.dmChanged,
        (_) => _onDmMessageChanged(server.id),
      )
      // A level changed somewhere else — the phone, another desktop. Without
      // this the setting is per-device in everything but storage, so the window
      // you left open goes on notifying you about a channel you muted an hour
      // ago. Every event re-seeds rather than being applied on its own, because
      // the answer is a chain across three scopes and a re-seed is one round
      // trip that already returns all of it.
      ..onBroadcast(ServerEvent.prefs, (_) => unawaited(_seed(server.id)));
    _subs[server.id] = _ServerSub(
      client: client,
      topics: [shared, own],
      token: server.token,
      userId: userId,
    );
    unawaited(_seed(server.id));
  }

  /// Hold one topic per private channel the caller can see, and let the rest
  /// go.
  ///
  /// A private channel's messages cannot go to the server's topic — that is
  /// everybody — so before this the database announced them to each member
  /// separately, one write per person who could see the channel. Now it says
  /// it once on the channel's own topic and this is what listens.
  ///
  /// Which channels those are is the caller's own list: `get_server_details`
  /// returns the private channels they may open and no others, so the set of
  /// topics here is a set of topics the server will admit. A channel that
  /// appears, disappears, or turns out to be theirs after all arrives as a
  /// change to that list, which is why this is reconciled on every pass
  /// rather than set up once.
  void _syncPrivateChannels(Server server) {
    final sub = _subs[server.id];
    if (sub == null) return;
    final realtime = _session.realtime;

    final wanted = <String>{
      for (final channel in server.channels)
        if (channel.isPrivate) channel.id,
    };

    for (final id in sub.privateChannels.keys.toList()) {
      if (wanted.contains(id)) continue;
      unawaited(sub.privateChannels.remove(id)?.release());
    }

    for (final id in wanted) {
      if (sub.privateChannels.containsKey(id)) continue;
      final lease = realtime.join(server, ServerTopics.channel(id));
      if (lease == null) continue;
      lease
        ..onBroadcast(
          ServerEvent.message,
          (message) =>
              _onChannelMessage(server.id, BroadcastPayload.of(message)),
        )
        ..onBroadcast(
          ServerEvent.messageChanged,
          (message) =>
              _onChannelMessageChanged(server.id, BroadcastPayload.of(message)),
        );
      sub.privateChannels[id] = lease;
    }
  }

  void _teardownServer(String serverId) {
    final sub = _subs.remove(serverId);
    if (sub == null) return;
    _forgetPeerNames(serverId);
    if (!isClosed) emit(state.clearedServer(serverId));
    for (final topic in [...sub.topics, ...sub.privateChannels.values]) {
      unawaited(topic.release());
    }
  }
}

/// A single server's unread subscription, and the shared client its REST
/// calls go out on.
class _ServerSub {
  final SupabaseClient client;

  /// The two that are always held: the server's topic and the caller's own.
  final List<RealtimeLease> topics;

  /// One per private channel the caller can see, keyed by channel id, so the
  /// set can be reconciled as channels and seats come and go.
  final Map<String, RealtimeLease> privateChannels = {};

  final String userId;
  String token;

  _ServerSub({
    required this.client,
    required this.topics,
    required this.userId,
    required this.token,
  });
}
