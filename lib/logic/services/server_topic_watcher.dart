import 'dart:async';

import '../../data/classes/server.dart';
import '../../data/repositories/session_repository.dart';
import 'server_realtime.dart';

/// Listens for one thing the database says about one server: its channels
/// moved, its member list did, your own row did.
///
/// The bookkeeping is the same wherever this is wanted, and it is all here:
/// re-subscribing when the server becomes usable or goes away, holding off the first join while a
/// hydrated token still reads as near-expiry, and coalescing a burst into one
/// refresh. The join itself is on the server's shared connection
/// ([ServerRealtime]), which follows the JWT as it rotates, and is shared with
/// everything else listening on the same topic.
///
/// What arrives is a doorbell, not a delta: the authoritative read is whatever
/// [onChanged] goes and fetches, which also keeps the shape identical to the
/// first load and picks up the token refresh that path already handles.
class ServerTopicWatcher {
  /// One logical change often writes several rows; refresh once for the burst.
  static const _coalesce = Duration(milliseconds: 250);

  /// Where the server list, the selection and the connection are.
  final SessionRepository session;

  /// The server to watch. Always one named server: a watcher that followed
  /// the selection moved a call's roster to whichever server was being read
  /// (`ServerContext` holds one per server instead).
  final String watchedServerId;

  /// The topic to listen on, for the watched server.
  final String Function(Server server) topicOf;

  /// What to listen for there.
  final String event;

  /// Whether the topic is still open to a member the server has banned: only
  /// their own, where the lifted ban is heard. Every other watcher stops at a
  /// ban, as the server refuses its topic ([Server.admitsUs]).
  final bool whileBanned;

  /// [event] was said on the watched server.
  final void Function() onChanged;

  /// The watched server is now [server], or nothing — it became usable or
  /// went away. Always fires before the
  /// first [onChanged] for that server.
  final void Function(Server? server) onServerChanged;

  StreamSubscription<void>? _serverSub;
  RealtimeLease? _lease;
  String? _serverId;
  Timer? _debounce;
  bool _disposed = false;

  ServerTopicWatcher({
    required this.session,
    required this.topicOf,
    required this.event,
    required this.onChanged,
    required this.onServerChanged,
    required this.watchedServerId,
    this.whileBanned = false,
  }) {
    _serverSub = session.changes.listen((_) => _sync());
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
      _sync();
    });
  }

  /// The server currently being watched, or null.
  String? get serverId => _serverId;

  void _sync() {
    final server = session.serverById(watchedServerId);
    if (server == null ||
        server.supabaseKey == null ||
        server.user == null ||
        (!whileBanned && !server.admitsUs)) {
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

  void _subscribe(Server server) {
    _lease = session.realtime.join(server, topicOf(server))
      ?..onBroadcast(event, (_) => _schedule());
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
