import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/services/broadcast_payload.dart';
import 'package:rift/logic/services/key_sweep_doorbell.dart';
import 'package:rift/logic/services/server_realtime.dart';

/// A `sweep` ring that announces keys already sealed names their channels, so
/// an app showing another channel, or in another call, lets it go. A ring
/// naming nothing — the database's, a member asking for a key, an older app's
/// — still means "look".
void main() {
  group('channelsOf', () {
    test('a named ring gives its channels', () {
      expect(
        BroadcastPayload.channelsOf({
          'event': 'sweep',
          'channels': ['c1', 'c2'],
        }),
        {'c1', 'c2'},
      );
      expect(
        BroadcastPayload.channelsOf({
          'payload': {
            'channels': ['c1'],
          },
        }),
        {'c1'},
      );
    });

    test('anything else names none', () {
      expect(BroadcastPayload.channelsOf(const {}), isNull);
      expect(BroadcastPayload.channelsOf({'channels': []}), isNull);
      expect(BroadcastPayload.channelsOf({'channels': 'c1'}), isNull);
      expect(
        BroadcastPayload.channelsOf({
          'channels': ['c1', 7],
        }),
        isNull,
      );
      expect(
        BroadcastPayload.channelsOf({
          'channels': [
            for (var i = 0; i <= BroadcastPayload.maxNamedChannels; i++) 'c$i',
          ],
        }),
        isNull,
      );
    });
  });

  group('the doorbell', () {
    final server = Server.fromJoin('http://127.0.0.1:9/a', 'jwt', {
      'server_id': 'a',
      'name': 'a',
      'supabase_key': 'anon',
    });
    late StreamController<List<Server>> servers;
    late ServerRealtime realtime;
    late KeySweepDoorbell listener;
    late KeySweepDoorbell ringer;
    late List<Set<String>?> heard;

    setUp(() {
      servers = StreamController<List<Server>>.broadcast();
      realtime = ServerRealtime(
        servers: servers.stream,
        current: () => [server],
        post: (url, {headers, body}) async => http.Response('', 202),
      );
      heard = [];
      listener = KeySweepDoorbell()..listen(realtime, server, heard.add);
      ringer = KeySweepDoorbell()..listen(realtime, server, (_) {});
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await listener.stop();
      await ringer.stop();
      await realtime.dispose();
      await servers.close();
    });

    // A throttled answer: the first ring's settle, then a wait out the gap.
    Future<void> answered() =>
        Future<void>.delayed(const Duration(milliseconds: 400));

    test('rings in one answer hand over every channel they named', () async {
      ringer
        ..ring(channels: ['c1'])
        ..ring(channels: ['c2', 'c1']);
      await answered();
      expect(heard, [
        {'c1', 'c2'},
      ]);
    });

    test('one ring naming nothing makes the answer "look"', () async {
      ringer
        ..ring(channels: ['c1'])
        ..ring();
      await answered();
      expect(heard, [null]);
    });

    test('a ring with nothing to name names nothing', () async {
      ringer.ring(channels: const []);
      await answered();
      expect(heard, [null]);
    });
  });
}
