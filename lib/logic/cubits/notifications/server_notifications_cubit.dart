import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../services/notification_service.dart';
import '../../services/window_focus_service.dart';
import '../server/server_cubit.dart';

/// One authenticated Realtime subscription per selected server to its
/// `notifications` table (Postgres Changes, RLS-scoped to `auth.uid()`).
///
/// Rows are fanned out by `send_message`, so this covers every channel — even
/// ones the user never opened — with a single subscription. On a new row we
/// raise an OS notification while the window is unfocused. State is a simple
/// session counter (future unread badge).
class ServerNotificationsCubit extends Cubit<int> {
  final ServerCubit _serverCubit;
  StreamSubscription<ServerState>? _serverSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _serverId;
  String? _token;

  ServerNotificationsCubit({required ServerCubit serverCubit})
      : _serverCubit = serverCubit,
        super(0) {
    _serverSub = serverCubit.stream.listen((_) => _sync());
    _sync();
  }

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
      final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
      client.realtime.setAuth(server.token);
      _client = client;
      _channel = client.channel('notifications:${server.id}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: server.user!.id,
          ),
          callback: _onInsert,
        )
        ..subscribe();
      return;
    }

    // Same server, token refreshed (silent re-auth) → update realtime auth so
    // the subscription's RLS keeps matching after the old JWT expires.
    if (server.token != _token) {
      _token = server.token;
      _client?.realtime.setAuth(server.token);
    }
  }

  void _onInsert(PostgresChangePayload payload) {
    if (isClosed || WindowFocusService.instance.isFocused) return;
    final channelId = payload.newRecord['channel_id'] as String?;
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
      body: channelName != null ? 'New message in #$channelName' : 'New message',
    );
    emit(state + 1);
  }

  Future<void> _teardown() async {
    _serverId = null;
    _token = null;
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    try {
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _teardown();
    return super.close();
  }
}
