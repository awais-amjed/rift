import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../../data/classes/server.dart';

typedef RealtimePayload = Map<String, dynamic>;
typedef RealtimeListener = void Function(RealtimePayload payload);

/// Hands a payload to every holder of a topic listening under a key. What a
/// topic's first holder is given, to route the bindings that must be declared
/// in the join itself — table changes and presence — to all its holders.
typedef RealtimeDispatch = void Function(String key, RealtimePayload payload);

/// One Realtime connection per self-hosted server, shared by everything that
/// listens to it, and one join per topic on that connection.
///
/// Every `SupabaseClient` opens a WebSocket of its own, and a server counts
/// sockets, not people: its Realtime tenant admits a fixed number of them
/// (the console's default is 1,000), so each client a feature built for
/// itself took one more place. Nine features each did, and a member looking
/// at a server held eight sockets to it — a server was full at about a
/// hundred and twenty-five people online.
///
/// A topic joined twice on one socket is worse than wasteful: the server keeps
/// the newer join and closes the older, so the first holder goes deaf. Holders
/// of a topic therefore share its join, and each hears it through [RealtimeLease].
///
/// Every topic is private: the server admits a join only if its rules
/// (`app.can_use_topic`, migration 017) say this member may hear it. So the
/// connection carries the member's JWT, followed as it rotates — a join on an
/// expired token is refused, and one whose token ran out is closed.
class ServerRealtime {
  final SupabaseClient Function(String url, String key) _connect;
  final Future<http.Response> Function(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  })
  _post;
  final List<Server> Function() _current;
  final Map<String, _Connection> _connections = {};
  StreamSubscription<List<Server>>? _serversSub;

  /// [servers] and [current] are the server list as it changes and as it is
  /// now — the only place a token is read from. A holder's own [Server] may be
  /// a snapshot from before the last rotation, and trusting it would put
  /// everybody's joins back on a token that has already expired.
  ServerRealtime({
    required Stream<List<Server>> servers,
    required List<Server> Function() current,
    SupabaseClient Function(String url, String key)? connect,
    Future<http.Response> Function(
      Uri url, {
      Map<String, String>? headers,
      Object? body,
    })?
    post,
  }) : _connect = connect ?? SupabaseClient.new,
       _post = post ?? http.post,
       _current = current {
    _serversSub = servers.listen(_follow);
  }

  /// [server]'s shared client, carrying the member's token — REST calls may
  /// use it too. Null for a server with no anon key.
  SupabaseClient? clientFor(Server server) => _connectionFor(server)?.client;

  /// Joins [topic] on [server]'s connection, or shares the join already there.
  ///
  /// [setUp] declares what has to be part of the join itself, and runs only for
  /// the topic's first holder: the server fixes a join's table filters when it
  /// accepts it, so a later holder cannot add any. Holders of one topic must
  /// therefore want the same thing from it, which the topic's name is what
  /// guarantees. [onStatus] hears every status the join reports, and the
  /// current one straight away when the topic is already joined.
  ///
  /// Null for a server with no anon key.
  RealtimeLease? join(
    Server server,
    String topic, {
    void Function(RealtimeChannel channel, RealtimeDispatch dispatch)? setUp,
    void Function(RealtimeSubscribeStatus status)? onStatus,
  }) {
    final connection = _connectionFor(server);
    if (connection == null) return null;

    final joined = connection.topics[topic] ??= _joinTopic(
      connection,
      topic,
      setUp,
    );
    joined.holders++;
    final lease = RealtimeLease._(this, server.id, topic, joined);
    if (onStatus != null) {
      joined.statusListeners.add(onStatus);
      lease._statusListener = onStatus;
      final current = joined.status;
      // Not called from in here: the holder is usually still assigning the
      // lease this returns.
      if (current != null) scheduleMicrotask(() => onStatus(current));
    }
    return lease;
  }

  /// Send [event] to [topic] without joining it — somebody else's topic,
  /// which the rules let a member send to but never hear. Best-effort, like
  /// every broadcast here.
  ///
  /// Over Realtime's HTTP endpoint rather than the socket: a socket may only
  /// send on a topic it has joined, and joining is exactly what is refused.
  Future<void> ring(
    Server server,
    String topic,
    String event,
    RealtimePayload payload,
  ) async {
    final client = clientFor(server);
    if (client == null) return;
    try {
      await _post(
        Uri.parse('${server.supabaseUrl}/realtime/v1/api/broadcast'),
        headers: {...client.headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': [
            {
              'topic': topic,
              'event': event,
              'payload': payload,
              'private': true,
            },
          ],
        }),
      );
    } catch (_) {}
  }

  _Topic _joinTopic(
    _Connection connection,
    String topic,
    void Function(RealtimeChannel channel, RealtimeDispatch dispatch)? setUp,
  ) {
    final channel = connection.client.channel(
      topic,
      opts: const RealtimeChannelConfig(private: true),
    );
    final joined = _Topic(channel);
    setUp?.call(channel, joined.dispatch);
    channel.subscribe((status, [_]) {
      joined.status = status;
      for (final listener in [...joined.statusListeners]) {
        listener(status);
      }
    });
    return joined;
  }

  _Connection? _connectionFor(Server server) {
    final existing = _connections[server.id];
    if (existing != null) return existing;
    Server? latest;
    for (final candidate in _current()) {
      if (candidate.id == server.id) latest = candidate;
    }
    final current = latest ?? server;
    final key = current.supabaseKey;
    if (key == null) return null;
    final connection = _Connection(_connect(current.supabaseUrl, key));
    connection.authorise(current.token, key);
    return _connections[server.id] = connection;
  }

  /// Keeps each connection on its server's current token, and closes the
  /// connection of a server that has left the list.
  void _follow(List<Server> servers) {
    final byId = {for (final server in servers) server.id: server};
    for (final id in _connections.keys.toList()) {
      final server = byId[id];
      final key = server?.supabaseKey;
      if (server == null || key == null) {
        unawaited(_close(id));
      } else {
        _connections[id]!.authorise(server.token, key);
      }
    }
  }

  Future<void> _release(RealtimeLease lease) async {
    final connection = _connections[lease._serverId];
    final joined = lease._topic;
    for (final entry in lease._listeners) {
      joined.listeners[entry.key]?.remove(entry.value);
    }
    final status = lease._statusListener;
    if (status != null) joined.statusListeners.remove(status);
    joined.holders--;
    if (connection == null || joined.holders > 0) return;
    if (!identical(connection.topics[lease._name], joined)) return;

    connection.topics.remove(lease._name);
    if (connection.topics.isEmpty) {
      await _close(lease._serverId);
      return;
    }
    try {
      await connection.client.removeChannel(joined.channel);
    } catch (_) {}
  }

  /// Closes the socket without leaving its topics one by one: the server drops
  /// a closed socket's joins itself, and waiting for each leave to be answered
  /// only holds this up — by a full timeout each when the server is gone.
  Future<void> _close(String serverId) async {
    final connection = _connections.remove(serverId);
    if (connection == null) return;
    try {
      await connection.client.dispose();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _serversSub?.cancel();
    for (final id in _connections.keys.toList()) {
      await _close(id);
    }
  }

  /// How many sockets are open — one per server with anything joined.
  int get connectionCount => _connections.length;

  /// How many joins [serverId]'s connection holds.
  int topicCount(String serverId) => _connections[serverId]?.topics.length ?? 0;
}

/// One holder's share of a topic.
class RealtimeLease {
  final ServerRealtime _owner;
  final String _serverId;
  final String _name;
  final _Topic _topic;
  final List<MapEntry<String, RealtimeListener>> _listeners = [];
  void Function(RealtimeSubscribeStatus status)? _statusListener;
  bool _released = false;

  RealtimeLease._(this._owner, this._serverId, this._name, this._topic);

  /// The shared join, for what only a channel can do — presence above all.
  RealtimeChannel get channel => _topic.channel;

  /// Hear [event] broadcasts on this topic.
  void onBroadcast(String event, RealtimeListener listener) {
    final key = 'broadcast:$event';
    if (_topic.boundBroadcasts.add(event)) {
      // Broadcasts are matched on this side of the socket, so one binding per
      // event can be added at any time and fanned out from there.
      _topic.channel.onBroadcast(
        event: event,
        callback: (payload) => _topic.dispatch(key, payload),
      );
    }
    on(key, listener);
  }

  /// Hear what the topic's [ServerRealtime.join] setUp dispatches under [key].
  void on(String key, RealtimeListener listener) {
    if (_released) return;
    _topic.listeners.putIfAbsent(key, () => {}).add(listener);
    _listeners.add(MapEntry(key, listener));
  }

  /// Broadcast [event] to everyone else on the topic. Best-effort: a failure
  /// is dropped, since every broadcast here is a nudge whose truth is in the
  /// database.
  void send(String event, RealtimePayload payload) {
    if (_released) return;
    unawaited(_send(event, payload));
  }

  Future<void> _send(String event, RealtimePayload payload) async {
    try {
      // A copy: the channel writes its own fields into the map it is handed,
      // and callers pass constants.
      await _topic.channel.sendBroadcastMessage(
        event: event,
        payload: {...payload},
      );
    } catch (_) {}
  }

  /// Stop hearing this topic. The join is left once nobody holds it, and the
  /// connection closed once it holds nothing.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _owner._release(this);
  }
}

class _Connection {
  final SupabaseClient client;
  final Map<String, _Topic> topics = {};
  String? _token;

  _Connection(this.client);

  /// Points REST and Realtime at [token]. A join outlives the token it was
  /// made with only if Realtime is told the new one.
  void authorise(String token, String anonKey) {
    if (token == _token) return;
    _token = token;
    client.headers = {
      'apikey': anonKey,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    if (token.isNotEmpty) unawaited(client.realtime.setAuth(token));
  }
}

class _Topic {
  final RealtimeChannel channel;
  final Map<String, Set<RealtimeListener>> listeners = {};
  final Set<String> boundBroadcasts = {};
  final Set<void Function(RealtimeSubscribeStatus status)> statusListeners = {};
  RealtimeSubscribeStatus? status;
  int holders = 0;

  _Topic(this.channel);

  void dispatch(String key, RealtimePayload payload) {
    for (final listener in [...?listeners[key]]) {
      listener(payload);
    }
  }
}
