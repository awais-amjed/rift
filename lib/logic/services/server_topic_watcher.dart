import 'dart:async';
import 'dart:math';

import '../../data/classes/server.dart';
import '../../data/repositories/session_repository.dart';
import 'broadcast_payload.dart';
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
/// first load and picks up the token refresh that path already handles. A
/// ring may say *who* it is about (`members` does, since self-host 062), and
/// then [onNamed] hears whom, so only they are read again.
///
/// A doorbell rung while the topic was down is lost, and nothing rings it
/// again, so the topic opening after a failure rings it here
/// ([RealtimeLease.onReopen]). Without that, a member list read while its
/// server could not be reached stayed empty after the server came back, until
/// Rift was restarted (a server that hung for two hours, Oct 26 2026).
class ServerTopicWatcher {
  /// One logical change often writes several rows; refresh once for the burst.
  static const _coalesce = Duration(milliseconds: 250);

  /// The longest a burst that keeps ringing holds its answer, past its first
  /// ring and the spread: rings arriving faster than [_coalesce] once put it
  /// off for as long as they came.
  static const _longestBurst = Duration(seconds: 1);

  /// The shortest time between two answers. Any member may ring a server's
  /// topic (`app.can_use_topic`), so a member looping one had every app on
  /// the server reading again as fast as Realtime carried the rings
  /// (security re-review, Nov 26). Nothing is lost: the next read sees what
  /// the rings in between announced.
  final Duration atMostEvery;

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
  final void Function()? onChanged;

  /// In place of [onChanged], for a ring that names what it is about
  /// (`{"ids": [...]}`, as `members` does): every id the burst named, or null
  /// when any ring in it named nothing, "anything may have moved", which is
  /// also what the topic opening again means.
  final void Function(Set<String>? ids)? onNamed;

  /// The most a burst waits beyond [_coalesce], chosen at random once per
  /// burst. Every app with the server on its list hears a ring at the same
  /// instant, and without it they all ask in the same quarter second; a
  /// watcher whose answer grows with the server's size spreads them out.
  final Duration Function()? spreadUpTo;

  /// The watched server is now [server], or nothing — it became usable or
  /// went away. Always fires before the
  /// first [onChanged] for that server.
  final void Function(Server? server) onServerChanged;

  StreamSubscription<void>? _serverSub;
  RealtimeLease? _lease;
  String? _serverId;
  Timer? _debounce;
  bool _disposed = false;

  /// What the burst so far has named; null once one named nothing.
  Set<String>? _named = {};

  /// The earliest the burst may answer, fixed by its first ring, so a ring
  /// arriving every second cannot keep pushing the spread out.
  DateTime? _notBefore;

  /// The latest the burst may answer, fixed by its first ring too.
  DateTime? _notAfter;

  DateTime? _lastAnswered;

  static final Random _random = Random();

  ServerTopicWatcher({
    required this.session,
    required this.topicOf,
    required this.event,
    this.onChanged,
    this.onNamed,
    this.spreadUpTo,
    required this.onServerChanged,
    required this.watchedServerId,
    this.whileBanned = false,
    this.atMostEvery = const Duration(seconds: 2),
  }) : assert(
         (onChanged == null) != (onNamed == null),
         'one of onChanged and onNamed',
       ) {
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
      ?..onBroadcast(event, (message) => _schedule(message))
      ..onReopen(() => _schedule(null));
  }

  /// [message] is the ring heard, or null for the topic opening again.
  void _schedule(Map<String, dynamic>? message) {
    final ids = message == null ? null : BroadcastPayload.idsOf(message);
    if (ids == null) {
      _named = null;
    } else {
      _named?.addAll(ids);
    }

    final now = DateTime.now();
    if (_notBefore == null) {
      final spread = spreadUpTo?.call() ?? Duration.zero;
      var first = now.add(
        _coalesce +
            Duration(
              milliseconds: spread.inMilliseconds <= 0
                  ? 0
                  : _random.nextInt(spread.inMilliseconds + 1),
            ),
      );
      final gapEnds = _lastAnswered?.add(atMostEvery);
      if (gapEnds != null && gapEnds.isAfter(first)) first = gapEnds;
      _notBefore = first;
      _notAfter = first.add(_longestBurst);
    }
    var at = now.add(_coalesce);
    if (at.isBefore(_notBefore!)) at = _notBefore!;
    if (at.isAfter(_notAfter!)) at = _notAfter!;
    _debounce?.cancel();
    _debounce = Timer(at.difference(now), _fire);
  }

  void _fire() {
    final named = _named;
    _named = {};
    _notBefore = null;
    _notAfter = null;
    _lastAnswered = DateTime.now();
    final onNamed = this.onNamed;
    if (onNamed != null) {
      onNamed(named);
    } else {
      onChanged?.call();
    }
  }

  void _teardown() {
    _debounce?.cancel();
    _debounce = null;
    _named = {};
    _notBefore = null;
    _notAfter = null;
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
