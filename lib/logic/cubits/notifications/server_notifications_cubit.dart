import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/server.dart';
import '../../services/notification_service.dart';
import '../../services/window_focus_service.dart';
import '../channel_chat/channel_chat_cubit.dart';
import '../server/server_cubit.dart';

part 'server_notifications_state.dart';

/// One authenticated Realtime + REST connection **per joined server** to its
/// `notifications` table (RLS-scoped to `auth.uid()`), so unread badges and OS
/// notifications work everywhere at once — not just on the server you're looking
/// at. Rows are fanned out by `send_message`, so this covers channels the user
/// never opened, on servers they aren't currently viewing.
///
/// Responsibilities:
/// - **Per-(server, channel) unread** — each subscription is seeded by an
///   authenticated REST fetch and kept live by Postgres-Changes INSERTs.
/// - **OS notifications** while the window is unfocused (any server).
/// - **Read tracking** — opening a channel, a message landing in the open+
///   focused channel, or refocusing the window marks that channel's
///   notifications read (`read_at`), clearing the badge and letting the
///   retention job (migration 008) prune them.
/// - **Token freshness** — background servers' JWTs are refreshed before they
///   expire (via [ServerCubit.reAuthenticateServer]) so their subscriptions
///   don't lapse while another server is in focus.
class ServerNotificationsCubit extends Cubit<NotificationsState> {
  final ServerCubit _serverCubit;
  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<ChannelChatState>? _chatSub;
  Timer? _refreshTimer;

  /// Per-server live subscription + authenticated client, keyed by server id.
  final Map<String, _ServerSub> _subs = {};

  /// The open text channel and the server it belongs to (always the selected
  /// server). Messages arriving here while focused are read, not badged.
  String? _openServerId;
  String? _openChannelId;

  ServerNotificationsCubit({
    required ServerCubit serverCubit,
    required ChannelChatCubit chatCubit,
  }) : _serverCubit = serverCubit,
       super(const NotificationsState()) {
    _serverSub = serverCubit.stream.listen((_) => _sync());
    _chatSub = chatCubit.stream.listen(_onChatChanged);
    WindowFocusService.instance.focused.addListener(_onFocusChanged);
    if (chatCubit.state.channelId != null) {
      _openServerId = serverCubit.state.selectedServerId;
      _openChannelId = chatCubit.state.channelId;
    }
    // Keep background servers' JWTs fresh so their subscriptions don't lapse.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _sync());
    _sync();
  }

  // ── Subscription lifecycle (one per joined server) ────────────

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

  void _subscribe(Server server) {
    final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _authClient(client, server.supabaseKey!, server.token);
    final channel = client.channel('notifications:${server.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: server.user!.id,
        ),
        callback: (payload) => _onInsert(server.id, payload),
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

  /// Fetch a server's current unread rows and fold them into per-channel counts.
  /// The open channel is treated as already read.
  Future<void> _seed(String serverId) async {
    final sub = _subs[serverId];
    if (sub == null) return;
    try {
      final rows = await sub.client
          .from('notifications')
          .select('channel_id')
          .eq('user_id', sub.userId)
          .isFilter('read_at', null);

      final counts = <String, int>{};
      for (final row in rows) {
        final cid = row['channel_id'] as String?;
        if (cid == null) continue;
        if (serverId == _openServerId && cid == _openChannelId) continue;
        counts[cid] = (counts[cid] ?? 0) + 1;
      }
      if (isClosed || !_subs.containsKey(serverId)) return;
      emit(state.withServerCounts(serverId, counts));

      if (serverId == _openServerId && _openChannelId != null) {
        markChannelRead(serverId, _openChannelId!);
      }
    } catch (_) {
      // Best-effort — a failed seed just means no badges until the next event.
    }
  }

  // ── Live delivery ─────────────────────────────────────────────

  void _onInsert(String serverId, PostgresChangePayload payload) {
    if (isClosed) return;
    final channelId = payload.newRecord['channel_id'] as String?;
    if (channelId == null) return;
    final focused = WindowFocusService.instance.isFocused;

    // Looking at this exact channel → it's read; don't badge or notify.
    if (focused && serverId == _openServerId && channelId == _openChannelId) {
      markChannelRead(serverId, channelId);
      return;
    }

    emit(state.incremented(serverId, channelId));

    if (!focused) {
      final server = _serverById(serverId);
      String? channelName;
      for (final c in server?.channels ?? const []) {
        if (c.id == channelId) {
          channelName = c.name;
          break;
        }
      }
      NotificationService.instance.showMessage(
        title: server?.name ?? 'Rift',
        body: channelName != null
            ? 'New message in #$channelName'
            : 'New message',
      );
    }
  }

  // ── Read tracking ─────────────────────────────────────────────

  void _onChatChanged(ChannelChatState chatState) {
    final channelId = chatState.channelId;
    if (channelId == _openChannelId) return;
    _openChannelId = channelId;
    if (channelId != null) {
      _openServerId = _serverCubit.state.selectedServerId;
      if (_openServerId != null) markChannelRead(_openServerId!, channelId);
    } else {
      _openServerId = null;
    }
  }

  void _onFocusChanged() {
    if (WindowFocusService.instance.isFocused &&
        _openServerId != null &&
        _openChannelId != null) {
      markChannelRead(_openServerId!, _openChannelId!);
    }
  }

  /// Mark every unread notification for a channel read and clear its badge.
  /// Local state updates optimistically; the RLS UPDATE is best-effort (a
  /// failure self-heals on the next re-seed).
  void markChannelRead(String serverId, String channelId) {
    emit(state.clearedChannel(serverId, channelId));
    final sub = _subs[serverId];
    if (sub == null) return;
    unawaited(() async {
      try {
        await sub.client
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', sub.userId)
            .eq('channel_id', channelId)
            .isFilter('read_at', null);
      } catch (_) {}
    }());
  }

  /// Mark every unread notification on a server read and clear its badge.
  ///
  /// Same optimistic-then-best-effort shape as [markChannelRead], minus the
  /// channel filter: each server has its own database, so "no channel filter"
  /// already means "this server only".
  void markServerRead(String serverId) {
    emit(state.clearedServer(serverId));
    final sub = _subs[serverId];
    if (sub == null) return;
    unawaited(() async {
      try {
        await sub.client
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', sub.userId)
            .isFilter('read_at', null);
      } catch (_) {}
    }());
  }

  // ── Teardown ──────────────────────────────────────────────────

  Server? _serverById(String serverId) {
    for (final s in _serverCubit.state.servers) {
      if (s.id == serverId) return s;
    }
    return null;
  }

  void _teardownServer(String serverId) {
    final sub = _subs.remove(serverId);
    if (sub == null) return;
    if (!isClosed) emit(state.clearedServer(serverId));
    unawaited(() async {
      try {
        await sub.channel.unsubscribe();
        sub.client.removeAllChannels();
        await sub.client.dispose();
      } catch (_) {}
    }());
  }

  @override
  Future<void> close() async {
    WindowFocusService.instance.focused.removeListener(_onFocusChanged);
    _refreshTimer?.cancel();
    await _serverSub?.cancel();
    await _chatSub?.cancel();
    for (final id in _subs.keys.toList()) {
      _teardownServer(id);
    }
    return super.close();
  }
}

/// A single server's authenticated notifications connection.
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
