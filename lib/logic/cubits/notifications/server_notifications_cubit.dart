import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../services/notification_service.dart';
import '../../services/window_focus_service.dart';
import '../channel_chat/channel_chat_cubit.dart';
import '../server/server_cubit.dart';

part 'server_notifications_state.dart';

/// One authenticated Realtime + REST connection per selected server to its
/// `notifications` table (RLS-scoped to `auth.uid()`), driving:
///
/// - **per-channel unread badges** — seeded by a REST fetch on subscribe and
///   kept live by Postgres-Changes INSERTs (rows are fanned out by
///   `send_message`, so this covers channels the user never opened),
/// - **OS notifications** while the window is unfocused,
/// - **read tracking** — opening a channel (or refocusing the window while one
///   is open) marks its notifications read (`read_at`), which clears the badge
///   and lets the retention job (migration 008) prune them.
///
/// Scope is the selected server; switching servers re-seeds from that server's
/// table (the source of truth), so unread persists across sessions.
class ServerNotificationsCubit extends Cubit<NotificationsState> {
  final ServerCubit _serverCubit;
  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<ChannelChatState>? _chatSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _serverId;
  String? _token;
  String? _userId;

  /// The text channel currently open in the chat view (if any) — messages
  /// arriving here while focused are read immediately, not badged.
  String? _openChannelId;

  ServerNotificationsCubit({
    required ServerCubit serverCubit,
    required ChannelChatCubit chatCubit,
  })  : _serverCubit = serverCubit,
        super(const NotificationsState()) {
    _serverSub = serverCubit.stream.listen((_) => _sync());
    _chatSub = chatCubit.stream.listen(_onChatChanged);
    WindowFocusService.instance.focused.addListener(_onFocusChanged);
    _openChannelId = chatCubit.state.channelId;
    _sync();
  }

  // ── Server subscription lifecycle ─────────────────────────────

  Future<void> _sync() async {
    final server = _serverCubit.state.selectedServer;
    if (server == null ||
        server.supabaseKey == null ||
        server.user == null ||
        server.token.isEmpty) {
      await _teardown();
      return;
    }

    // New server → (re)subscribe with a fresh authenticated client.
    if (server.id != _serverId) {
      await _teardown();
      _serverId = server.id;
      _token = server.token;
      _userId = server.user!.id;
      final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
      _authClient(client, server.supabaseKey!, server.token);
      _client = client;
      _channel = client.channel('notifications:${server.id}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _userId,
          ),
          callback: _onInsert,
        )
        ..subscribe();
      await _seedUnread();
      return;
    }

    // Same server, token refreshed (silent re-auth) → update both transports so
    // the RLS subscription + REST calls keep matching after the old JWT expires.
    if (server.token != _token) {
      _token = server.token;
      if (_client != null) _authClient(_client!, server.supabaseKey!, server.token);
    }
  }

  /// Point both REST and Realtime at the user's JWT so RLS sees `auth.uid()`.
  void _authClient(SupabaseClient client, String anonKey, String token) {
    client.headers = {'apikey': anonKey, 'Authorization': 'Bearer $token'};
    client.realtime.setAuth(token);
  }

  /// Fetch current unread rows and fold them into per-channel counts. The open
  /// channel is treated as already read.
  Future<void> _seedUnread() async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return;
    try {
      final rows = await client
          .from('notifications')
          .select('channel_id')
          .eq('user_id', userId)
          .isFilter('read_at', null);

      final counts = <String, int>{};
      for (final row in rows) {
        final cid = row['channel_id'] as String?;
        if (cid == null || cid == _openChannelId) continue;
        counts[cid] = (counts[cid] ?? 0) + 1;
      }
      if (isClosed) return;
      emit(NotificationsState(unreadByChannel: counts));

      // Clear anything already accrued for the channel we're looking at.
      if (_openChannelId != null) markChannelRead(_openChannelId!);
    } catch (_) {
      // Best-effort — a failed seed just means no badges until the next event.
    }
  }

  // ── Live delivery ─────────────────────────────────────────────

  void _onInsert(PostgresChangePayload payload) {
    if (isClosed) return;
    final channelId = payload.newRecord['channel_id'] as String?;
    if (channelId == null) return;
    final focused = WindowFocusService.instance.isFocused;

    // Looking at this channel → it's read; don't badge or notify.
    if (channelId == _openChannelId && focused) {
      markChannelRead(channelId);
      return;
    }

    final next = Map<String, int>.from(state.unreadByChannel);
    next[channelId] = (next[channelId] ?? 0) + 1;
    emit(state.copyWith(unreadByChannel: next));

    if (!focused) {
      final server = _serverCubit.state.selectedServer;
      String? channelName;
      for (final c in server?.channels ?? const []) {
        if (c.id == channelId) {
          channelName = c.name;
          break;
        }
      }
      NotificationService.instance.showMessage(
        title: server?.name ?? 'Rift',
        body:
            channelName != null ? 'New message in #$channelName' : 'New message',
      );
    }
  }

  // ── Read tracking ─────────────────────────────────────────────

  void _onChatChanged(ChannelChatState chatState) {
    if (chatState.channelId == _openChannelId) return;
    _openChannelId = chatState.channelId;
    if (_openChannelId != null) markChannelRead(_openChannelId!);
  }

  void _onFocusChanged() {
    if (WindowFocusService.instance.isFocused && _openChannelId != null) {
      markChannelRead(_openChannelId!);
    }
  }

  /// Mark every unread notification for [channelId] read and clear its badge.
  /// Local state updates optimistically; the RLS UPDATE is best-effort (a
  /// failure self-heals on the next re-seed).
  void markChannelRead(String channelId) {
    if (state.unreadFor(channelId) > 0) {
      final next = Map<String, int>.from(state.unreadByChannel)..remove(channelId);
      emit(state.copyWith(unreadByChannel: next));
    }
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return;
    unawaited(() async {
      try {
        await client
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', userId)
            .eq('channel_id', channelId)
            .isFilter('read_at', null);
      } catch (_) {}
    }());
  }

  // ── Teardown ──────────────────────────────────────────────────

  Future<void> _teardown() async {
    _serverId = null;
    _token = null;
    _userId = null;
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    if (!isClosed && state.unreadByChannel.isNotEmpty) {
      emit(const NotificationsState());
    }
    try {
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    WindowFocusService.instance.focused.removeListener(_onFocusChanged);
    await _serverSub?.cancel();
    await _chatSub?.cancel();
    await _teardown();
    return super.close();
  }
}
