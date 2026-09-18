import 'dart:async';

import 'package:supabase/supabase.dart';

import '../../data/classes/server.dart';
import '../cubits/server/server_cubit.dart';
import 'server_realtime.dart';

/// Keeps one Realtime subscription pointed at [table] on the selected server.
///
/// The bookkeeping is the same wherever this is wanted, and it is all here:
/// re-subscribing on a server switch, holding off the first subscribe while a
/// hydrated token still reads as near-expiry, and coalescing a burst of row
/// events into one refresh. The join itself is on the server's shared
/// connection ([ServerRealtime]), which follows the JWT as it rotates.
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
  RealtimeLease? _lease;
  String? _serverId;
  Timer? _debounce;
  bool _disposed = false;

  ServerTableWatcher({
    required this.serverCubit,
    required this.table,
    required this.onChanged,
    required this.onServerChanged,
  }) {
    _serverSub = serverCubit.stream.listen(_sync);
    // Deferred a microtask, never called straight from here. Consumers hold
    // the watcher in a `late final` field that this very expression is
    // initialising, so a callback fired from the constructor reaches an object
    // whose own field isn't assigned yet — `onServerChanged` refreshes, the
    // refresh reads `watcher.serverId`, and the app dies on launch with a
    // LateInitializationError. A microtask still lands before anything from
    // the stream, which is delivered asynchronously, so the promise that
    // [onServerChanged] fires first is kept.
    scheduleMicrotask(() {
      if (_disposed) return;
      _sync(serverCubit.state);
    });
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
      onServerChanged(server);
    }

    // Hydrated tokens read as near-expiry at startup, and joining with one
    // makes a join that is already dead. The refresh that triggers comes back
    // through here as a token change, and we join then. After that the shared
    // connection follows the token itself.
    if (_lease == null && !server.isTokenNearExpiry) _subscribe(server);
  }

  /// Another watcher of the same table on the same server shares this join —
  /// the topic is named for exactly that.
  void _subscribe(Server server) {
    _lease = serverCubit.realtime.join(
      server,
      '$table:${server.id}',
      setUp: (channel, dispatch) => channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => dispatch('change', const {}),
      ),
    )?..on('change', (_) => _schedule());
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_coalesce, onChanged);
  }

  void _teardown() {
    _debounce?.cancel();
    _debounce = null;
    _serverId = null;

    final lease = _lease;
    _lease = null;
    unawaited(lease?.release());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _serverSub?.cancel();
    _serverSub = null;
    _teardown();
  }
}
