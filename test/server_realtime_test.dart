import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/services/server_realtime.dart';

// A port nothing listens on: the socket is refused at once and closes at once,
// where a host that doesn't resolve holds every disconnect for six seconds.
Server _server(String id, {String token = 'jwt-1', String? key = 'anon'}) =>
    Server.fromJoin('http://127.0.0.1:9/$id', token, {
      'server_id': id,
      'name': id,
      'supabase_key': key,
    });

/// A registry over a server list the test controls. What is under test is the
/// bookkeeping, not the sockets.
class _Harness {
  final controller = StreamController<List<Server>>.broadcast();
  List<Server> servers;
  late final ServerRealtime realtime = ServerRealtime(
    servers: controller.stream,
    current: () => servers,
  );

  _Harness(this.servers);

  Future<void> publish(List<Server> next) async {
    servers = next;
    controller.add(next);
    await Future<void>.delayed(Duration.zero);
  }

  /// Closing a socket whose connect is still in flight waits out a timeout;
  /// one refused a moment ago closes straight away.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  Future<void> close() async {
    await settle();
    await realtime.dispose();
    await controller.close();
  }
}

void main() {
  // The measured problem: nine features, nine sockets to the same server.
  test('everything on one server shares one connection', () async {
    final a = _server('a');
    final h = _Harness([a]);

    h.realtime.join(a, 'presence:a');
    h.realtime.join(a, 'unread:a');
    h.realtime.join(a, 'chat:general');

    expect(h.realtime.connectionCount, 1);
    expect(h.realtime.topicCount('a'), 3);
    await h.close();
  });

  test('each server has its own connection', () async {
    final a = _server('a');
    final b = _server('b');
    final h = _Harness([a, b]);

    h.realtime.join(a, 'unread:a');
    h.realtime.join(b, 'unread:b');

    expect(h.realtime.connectionCount, 2);
    await h.close();
  });

  // Joining one topic twice on a socket makes the server drop the first join,
  // so two holders must share it — and both must still hear it.
  test('two holders of a topic share its join and both hear it', () async {
    final a = _server('a');
    final h = _Harness([a]);
    var setUps = 0;
    late RealtimeDispatch dispatch;
    void setUp(_, RealtimeDispatch d) {
      setUps++;
      dispatch = d;
    }

    final heard = <String>[];
    final first = h.realtime.join(a, 'users:a', setUp: setUp)!
      ..on('change', (_) => heard.add('first'));
    h.realtime
        .join(a, 'users:a', setUp: setUp)!
        .on('change', (_) => heard.add('second'));

    expect(setUps, 1);
    expect(h.realtime.topicCount('a'), 1);

    dispatch('change', const {});
    expect(heard, ['first', 'second']);

    await first.release();
    dispatch('change', const {});
    expect(heard, ['first', 'second', 'second']);
    expect(h.realtime.topicCount('a'), 1);
    await h.close();
  });

  test('the connection closes when nothing holds anything on it', () async {
    final a = _server('a');
    final h = _Harness([a]);

    final one = h.realtime.join(a, 'keysweep:a')!;
    final two = h.realtime.join(a, 'keysweep:a')!;
    await h.settle();
    await one.release();
    expect(h.realtime.connectionCount, 1);
    await two.release();

    expect(h.realtime.connectionCount, 0);
    await h.close();
  });

  test('releasing twice is releasing once', () async {
    final a = _server('a');
    final h = _Harness([a]);

    final one = h.realtime.join(a, 'chat:x')!;
    h.realtime.join(a, 'chat:x');
    await one.release();
    await one.release();

    expect(h.realtime.topicCount('a'), 1);
    await h.close();
  });

  test('a server leaving the list takes its connection with it', () async {
    final a = _server('a');
    final b = _server('b');
    final h = _Harness([a, b]);
    h.realtime.join(a, 'unread:a');
    h.realtime.join(b, 'unread:b');

    await h.publish([b]);

    expect(h.realtime.connectionCount, 1);
    expect(h.realtime.topicCount('a'), 0);
    await h.close();
  });

  test('a server with no anon key has nothing to connect with', () async {
    final a = _server('a', key: null);
    final h = _Harness([a]);

    expect(h.realtime.join(a, 'unread:a'), isNull);
    expect(h.realtime.connectionCount, 0);
    await h.close();
  });

  test('a rotated token reaches the shared connection', () async {
    final a = _server('a');
    final h = _Harness([a]);
    h.realtime.join(a, 'unread:a');

    await h.publish([a.copyWith(token: 'jwt-2')]);

    expect(h.realtime.clientFor(a)!.headers['Authorization'], 'Bearer jwt-2');
    await h.close();
  });

  // A holder's own Server can be a snapshot from before the last rotation.
  // Believing it would put every join on the server back on a dead token.
  test('a stale snapshot does not roll the token back', () async {
    final stale = _server('a');
    final h = _Harness([stale.copyWith(token: 'jwt-2')]);

    h.realtime.join(stale, 'unread:a');
    h.realtime.join(stale, 'chat:x');

    expect(
      h.realtime.clientFor(stale)!.headers['Authorization'],
      'Bearer jwt-2',
    );
    await h.close();
  });

  // The channel writes into the payload it is handed; a constant used to take
  // the app down with an unhandled error the first time a doorbell rang.
  test('a constant payload can be sent', () async {
    final a = _server('a');
    final h = _Harness([a]);
    final lease = h.realtime.join(a, 'keysweep:a')!;

    lease.send('sweep', const {});
    await h.settle();

    await h.close();
  });
}
