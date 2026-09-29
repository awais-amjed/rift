import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/services/server_realtime.dart';
import 'package:supabase/supabase.dart' show RealtimeSubscribeStatus;

// A port nothing listens on: the socket is refused at once and closes at once,
// where a host that doesn't resolve holds every disconnect for six seconds.
Server _server(String id, {String token = 'jwt-1', String? key = 'anon'}) =>
    Server.fromJoin('http://127.0.0.1:9/$id', token, {
      'server_id': id,
      'name': id,
      'supabase_key': key,
    });

/// A JWT whose `exp` is [fromNow] away — in the past when negative. Only the
/// claims are read on this side; the signature is the server's business.
String _jwt(Duration fromNow) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().add(fromNow).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'exp': exp})}.sig';
}

/// A registry over a server list the test controls. What is under test is the
/// bookkeeping, not the sockets.
class _Harness {
  final controller = StreamController<List<Server>>.broadcast();
  List<Server> servers;
  final posts = <({Uri url, Map<String, String> headers, Object? body})>[];
  late final ServerRealtime realtime = ServerRealtime(
    servers: controller.stream,
    current: () => servers,
    post: (url, {headers, body}) async {
      posts.add((url: url, headers: headers ?? const {}, body: body));
      return http.Response('', 202);
    },
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

  // A launch whose stored token had expired joined its own topic with it, was
  // refused, and heard nothing all session: the client never asks again, and
  // a new token only reaches joins that succeeded.
  test(
    'a join refused under an old token is asked again with the new one',
    () async {
      final a = _server('a');
      final h = _Harness([a]);
      final heard = <String>[];
      h.realtime.join(a, 'user:me')!.onBroadcast('dm', (_) => heard.add('dm'));
      final refused = h.realtime.debugChannelOf('a', 'user:me');

      h.realtime.debugReportStatus(
        'a',
        'user:me',
        RealtimeSubscribeStatus.channelError,
      );
      expect(
        h.realtime.debugChannelOf('a', 'user:me'),
        same(refused),
        reason: 'refused under the current token: asking again is pointless',
      );

      await h.publish([a.copyWith(token: 'jwt-2')]);
      final rejoined = h.realtime.debugChannelOf('a', 'user:me');
      expect(rejoined, isNot(same(refused)));
      expect(h.realtime.topicCount('a'), 1);

      // The same lease still hears the topic on its new channel.
      rejoined!.trigger('broadcast', {'event': 'dm', 'payload': {}});
      expect(heard, ['dm']);
      await h.close();
    },
  );

  test(
    'a refusal that answers a token already replaced rejoins at once',
    () async {
      final a = _server('a');
      final h = _Harness([a]);
      h.realtime.join(a, 'user:me');
      final first = h.realtime.debugChannelOf('a', 'user:me');

      await h.publish([a.copyWith(token: 'jwt-2')]);
      expect(h.realtime.debugChannelOf('a', 'user:me'), same(first));

      h.realtime.debugReportStatus(
        'a',
        'user:me',
        RealtimeSubscribeStatus.channelError,
      );
      expect(h.realtime.debugChannelOf('a', 'user:me'), isNot(same(first)));
      await h.close();
    },
  );

  // What a dropped socket does: realtime_client walks its channel list firing
  // each one's error, and only after the walk schedules the reconnect. Two
  // things went wrong here after a token rotation. A rejoin that added to the
  // list during the walk threw out of it, so the reconnect was never
  // scheduled. And replacing a channel while the socket was down lost the
  // replacement from the socket's list, so the topic never joined again.
  test(
    'a socket drop leaves each topic on a channel the socket still has',
    () async {
      final a = _server('a');
      final h = _Harness([a]);
      h.realtime.join(a, 'user:me');
      h.realtime.join(a, 'server:a');
      await h.publish([a.copyWith(token: 'jwt-2')]);
      final first = h.realtime.debugChannelOf('a', 'user:me')!;

      expect(() {
        for (final channel in h.realtime.debugSocketChannels('a')) {
          channel.trigger('phx_error', 'socket closed');
        }
      }, returnsNormally);

      await h.settle();
      for (final topic in ['user:me', 'server:a']) {
        final channel = h.realtime.debugChannelOf('a', topic);
        expect(
          h.realtime.debugSocketChannels('a'),
          contains(same(channel)),
          reason: '$topic must stay on a channel the client will rejoin',
        );
      }
      expect(
        h.realtime.debugChannelOf('a', 'user:me'),
        same(first),
        reason: 'the client joins it again by itself, with the new token',
      );
      await h.close();
    },
  );

  // A launch finds the token it stored an hour or more ago. Joins sent on it
  // were refused seconds apart, timed out meanwhile, and the refusals and the
  // client's own retries of one topic knocked it off the socket for the
  // session.
  test('a join waits for a token that has not run out', () async {
    final stale = _server('a', token: _jwt(const Duration(hours: -3)));
    final h = _Harness([stale]);
    h.realtime.join(stale, 'user:me');
    final channel = h.realtime.debugChannelOf('a', 'user:me')!;
    expect(
      h.realtime.debugAwaitingToken('a', 'user:me'),
      isTrue,
      reason: 'nothing sent on a dead token',
    );

    await h.publish([stale.copyWith(token: _jwt(const Duration(hours: 1)))]);
    expect(h.realtime.debugChannelOf('a', 'user:me'), same(channel));
    expect(h.realtime.debugAwaitingToken('a', 'user:me'), isFalse);
    expect(h.realtime.debugSocketChannels('a'), contains(same(channel)));
    await h.close();
  });

  test('releasing a waiting topic leaves the others waiting', () async {
    final stale = _server('a', token: _jwt(const Duration(hours: -3)));
    final h = _Harness([stale]);
    final one = h.realtime.join(stale, 'user:me')!;
    h.realtime.join(stale, 'server:a');
    await one.release();

    await h.publish([stale.copyWith(token: _jwt(const Duration(hours: 1)))]);
    final other = h.realtime.debugChannelOf('a', 'server:a')!;
    expect(h.realtime.debugAwaitingToken('a', 'server:a'), isFalse);
    expect(h.realtime.debugSocketChannels('a'), [same(other)]);
    await h.close();
  });

  test('a token that is not a JWT is not held back', () async {
    final a = _server('a');
    final h = _Harness([a]);
    h.realtime.join(a, 'user:me');
    expect(h.realtime.debugAwaitingToken('a', 'user:me'), isFalse);
    await h.close();
  });

  test('a timed-out join is left to the client to ask again', () async {
    final a = _server('a');
    final h = _Harness([a]);
    h.realtime.join(a, 'user:me');
    final first = h.realtime.debugChannelOf('a', 'user:me');
    await h.publish([a.copyWith(token: 'jwt-2')]);

    h.realtime.debugReportStatus(
      'a',
      'user:me',
      RealtimeSubscribeStatus.timedOut,
    );
    await h.publish([a.copyWith(token: 'jwt-3')]);
    expect(h.realtime.debugChannelOf('a', 'user:me'), same(first));
    await h.close();
  });

  test('a joined topic is left alone when the token rotates', () async {
    final a = _server('a');
    final h = _Harness([a]);
    h.realtime.join(a, 'user:me');
    h.realtime.debugReportStatus(
      'a',
      'user:me',
      RealtimeSubscribeStatus.subscribed,
    );
    final joined = h.realtime.debugChannelOf('a', 'user:me');

    await h.publish([a.copyWith(token: 'jwt-2')]);
    expect(h.realtime.debugChannelOf('a', 'user:me'), same(joined));
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

  // Somebody else's topic can be sent to but not joined, so a DM's typing
  // indicator goes over HTTP — and has to say it is for a private topic, with
  // the member's token, or the server's rules turn it away.
  test(
    'ringing a topic posts a private broadcast with the member\'s token',
    () async {
      final a = _server('a', token: 'jwt-7');
      final h = _Harness([a]);

      await h.realtime.ring(a, 'user:peer', 'typing', {'from': 'me'});

      expect(h.posts, hasLength(1));
      final post = h.posts.single;
      expect(post.url.path, endsWith('/realtime/v1/api/broadcast'));
      expect(post.headers['Authorization'], 'Bearer jwt-7');
      final message =
          (jsonDecode(post.body! as String)['messages'] as List).single
              as Map<String, dynamic>;
      expect(message['topic'], 'user:peer');
      expect(message['event'], 'typing');
      expect(message['private'], isTrue);
      expect(message['payload'], {'from': 'me'});
      expect(h.realtime.connectionCount, 1);
      await h.close();
    },
  );
}
