import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../server/server_cubit.dart';

/// Realtime "something changed on this server" doorbell (Supabase Broadcast),
/// one topic per selected server — `server_events:<serverId>`.
///
/// Any member who makes a structural change (creating a channel, …) pings the
/// topic via [notifyServerChanged]; every subscribed member refreshes their
/// server details, so new channels appear without waiting for a reselect or
/// restart. Broadcast is ephemeral pub/sub, so — like the chat keysweep
/// doorbell — it needs no auth/RLS: the payload is just "go refresh", and the
/// authoritative state still comes from `get_server_details`.
///
/// Scoped to the selected server (that's the one whose channel list is shown);
/// other servers refresh on select.
class ServerEventsCubit extends Cubit<int> {
  final ServerCubit _serverCubit;
  StreamSubscription<ServerState>? _serverSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _serverId;

  ServerEventsCubit({required ServerCubit serverCubit})
    : _serverCubit = serverCubit,
      super(0) {
    _serverSub = serverCubit.stream.listen((_) => _sync());
    _sync();
  }

  void _sync() {
    final server = _serverCubit.state.selectedServer;
    if (server == null || server.supabaseKey == null) {
      _teardown();
      return;
    }
    if (server.id == _serverId) return; // already subscribed to this server

    _teardown();
    _serverId = server.id;
    final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _client = client;
    _channel = client.channel('server_events:${server.id}')
      ..onBroadcast(event: 'changed', callback: (_) => _onChanged())
      ..subscribe();
  }

  void _onChanged() {
    if (isClosed) return;
    unawaited(_serverCubit.refreshServerDetails());
  }

  /// Ping the selected server's topic so other members refresh.
  void notifyServerChanged() {
    try {
      _channel?.sendBroadcastMessage(event: 'changed', payload: {});
    } catch (_) {}
  }

  void _teardown() {
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    _serverId = null;
    unawaited(() async {
      try {
        await channel?.unsubscribe();
        client?.removeAllChannels();
        await client?.dispose();
      } catch (_) {}
    }());
  }

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    _teardown();
    return super.close();
  }
}
