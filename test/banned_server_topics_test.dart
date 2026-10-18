import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/services/server_topic_watcher.dart';
import 'package:rift/logic/services/server_topics.dart';

/// A server that has banned or kicked us refuses every topic but our own.
/// Joined anyway, each was refused and retried every few seconds for as long
/// as the server stayed on the device — the notification subscription even
/// with the server not selected.

const _me = ServerUser(
  id: 'me',
  username: 'me',
  displayName: 'Me',
  permissions: UserPermissions(),
);

/// Old enough that a watcher holds off joining, so nothing here opens a
/// socket; what is under test is whether it thinks the server is there.
Server _server({bool banned = false, bool joined = true}) => Server(
  id: 'srv',
  name: 'Lighthouse',
  supabaseUrl: 'https://srv.invalid',
  supabaseKey: 'anon',
  token: 'token',
  tokenIssuedAt: DateTime(2000),
  user: joined
      ? ServerUser(
          id: _me.id,
          username: _me.username,
          displayName: _me.displayName,
          permissions: _me.permissions,
          isBanned: banned,
          isKicked: banned,
        )
      : null,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a server admits us only while we are on it and not banned', () {
    expect(_server().admitsUs, isTrue);
    expect(_server(banned: true).admitsUs, isFalse);
    expect(_server(joined: false).admitsUs, isFalse);
  });

  group('a topic watcher', () {
    late SessionRepository session;
    setUp(() => session = SessionRepository());
    tearDown(() => session.dispose());

    /// The servers the watcher was told about, null for "gone".
    Future<(ServerTopicWatcher, List<String?>)> watch({
      bool whileBanned = false,
    }) async {
      final seen = <String?>[];
      final watcher = ServerTopicWatcher(
        session: session,
        watchedServerId: 'srv',
        topicOf: (server) => ServerTopics.server(server.id),
        event: 'event',
        onChanged: () {},
        onServerChanged: (server) => seen.add(server?.id),
        whileBanned: whileBanned,
      );
      await _settle();
      return (watcher, seen);
    }

    test('stops at a ban and starts again when it is lifted', () async {
      session.publish(servers: [_server()], selectedServerId: 'srv');
      final (watcher, seen) = await watch();
      expect(seen, ['srv']);

      session.publish(servers: [_server(banned: true)]);
      await _settle();
      expect(seen, ['srv', null]);
      expect(watcher.serverId, isNull);

      session.publish(servers: [_server()]);
      await _settle();
      expect(seen, ['srv', null, 'srv']);
      await watcher.dispose();
    });

    test('never starts on a server that has banned us', () async {
      session.publish(servers: [_server(banned: true)]);
      final (watcher, seen) = await watch();
      expect(seen, isEmpty);
      expect(watcher.serverId, isNull);
      await watcher.dispose();
    });

    test('on our own topic, keeps listening through a ban', () async {
      session.publish(servers: [_server(banned: true)]);
      final (watcher, seen) = await watch(whileBanned: true);
      expect(seen, ['srv'], reason: 'where the lifted ban is heard');
      expect(watcher.serverId, 'srv');
      await watcher.dispose();
    });
  });
}
