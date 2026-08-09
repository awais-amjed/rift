import 'dart:async';

import 'package:supabase/supabase.dart';

import '../../data/classes/server.dart';
import '../cubits/server/server_cubit.dart';

/// Keeps one Realtime subscription pointed at [table] on the selected server.
///
/// The bookkeeping is the same wherever this is wanted, and it is all here:
/// re-subscribing on a server switch, re-pointing Realtime at a rotated JWT (a
/// subscription dies with the token it was opened on), holding off the first
/// subscribe while a hydrated token still reads as near-expiry, and coalescing
/// a burst of row events into one refresh.
///
/// A row event is treated as a doorbell rather than a delta. Realtime re-checks
/// the migration-002 policies per subscriber, so what arrives is only what this
/// member could have selected anyway — but the authoritative read is whatever
/// [onChanged] goes and fetches, which also keeps the shape identical to the
/// first load and picks up the token refresh that path already handles.
class ServerTableWatcher {
  /// One logical change often writes several rows; refresh once for the burst.
  static const _coalesce = Duration(milliseconds: 250);

  final ServerCubit serverCubit;
  final String table;

  /// A row in [table] moved on the selected server.
  final void Function() onChanged;

  /// The selection moved to [server], or to nothing. Always fires before the
  /// first [onChanged] for that server.
  final void Function(Server? server) onServerChanged;

  StreamSubscription<ServerState>? _serverSub;
  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _serverId;
  String? _token;
  Timer? _debounce;

  ServerTableWatcher({
    required this.serverCubit,
    required this.table,
    required this.onChanged,
    required this.onServerChanged,
  }) {
    _serverSub = serverCubit.stream.listen(_sync);
    _sync(serverCubit.state);
  }

  /// The server currently being watched, or null.
  String? get serverId => _serverId;

  void _sync(ServerState state) {
    final server = state.selectedServer;
    if (server == null || server.supabaseKey == null || server.user == null) {
      if (_serverId == null) return;
      _teardown();
      onServerChanged(null);
      return;
    }

    if (server.id != _serverId) {
      _teardown();
      _serverId = server.id;
      _token = server.token;
      onServerChanged(server);
    } else if (server.token != _token) {
      // Silent re-auth rotated the JWT. Realtime has to be re-pointed at it or
      // the subscription dies with the token it was opened on.
      _token = server.token;
      _client?.realtime.setAuth(server.token);
    }

    // Hydrated tokens read as near-expiry at startup, and subscribing with one
    // opens a connection that is already dead. The refresh that triggers comes
    // back through here as a token change, and we subscribe then.
    if (_channel == null && !server.isTokenNearExpiry) _subscribe(server);
  }

  void _subscribe(Server server) {
    final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    // RLS has to see `auth.uid()`, so both transports carry the member's JWT.
    client.headers = {
      'apikey': server.supabaseKey!,
      'Authorization': 'Bearer ${server.token}',
    };
    client.realtime.setAuth(server.token);
    _client = client;
    _channel = client.channel('$table:${server.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _schedule(),
      )
      ..subscribe();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_coalesce, onChanged);
  }

  void _teardown() {
    _debounce?.cancel();
    _debounce = null;
    _serverId = null;
    _token = null;

    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    unawaited(() async {
      try {
        await channel?.unsubscribe();
        client?.removeAllChannels();
        await client?.dispose();
      } catch (_) {}
    }());
  }

  Future<void> dispose() async {
    await _serverSub?.cancel();
    _serverSub = null;
    _teardown();
  }
}
