import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/services/server_topic_watcher.dart';
import 'package:rift/logic/services/server_topics.dart';
import 'package:supabase/supabase.dart' show RealtimeSubscribeStatus;

/// In-memory stand-in so the hydrated cubits can be built in tests.
class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// A server that is ready to be watched: it has both an anon key and a member
/// row, which is what makes [ServerTopicWatcher] act on it.
ServerCubit _cubitWithSelectedServer(
  SessionRepository session, {
  String url = 'https://server.invalid',
  String token = 'jwt',
}) {
  final cubit = ServerCubit(session: session);
  cubit.addServer(url, token, {
    'server_id': 'srv-1',
    'name': 'Rift HQ',
    'supabase_key': 'anon-key',
    'user': {'id': 'u1', 'username': 'ada', 'display_name': 'Ada'},
    'channels': <Map<String, dynamic>>[],
  });
  return cubit;
}

/// A JWT that ran out the moment it was received. The watcher still joins
/// with it (it is not near expiry by the age the app goes by), but the shared
/// connection holds the join back for a fresh token, so no socket is opened
/// and the only statuses the topic hears are the ones the test reports.
String _spentJwt() {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'iat': now, 'exp': now})}.sig';
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('a topic that was down', () {
    late SessionRepository session;
    late ServerCubit serverCubit;
    late ServerTopicWatcher watcher;
    late int rings;
    final topic = ServerTopics.server('srv-1');

    setUp(() async {
      session = SessionRepository();
      serverCubit = _cubitWithSelectedServer(
        session,
        url: 'http://127.0.0.1:9',
        token: _spentJwt(),
      );
      rings = 0;
      watcher = ServerTopicWatcher(
        session: session,
        watchedServerId: 'srv-1',
        topicOf: (server) => ServerTopics.server(server.id),
        event: ServerEvent.members,
        onChanged: () => rings++,
        onServerChanged: (_) {},
      );
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      await watcher.dispose();
      await serverCubit.close();
      await session.dispose();
    });

    void report(RealtimeSubscribeStatus status) =>
        session.realtime.debugReportStatus('srv-1', topic, status);

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 400));

    test('a join that simply opens rings nothing', () async {
      report(RealtimeSubscribeStatus.subscribed);
      await settle();
      expect(rings, 0);
    });

    // A doorbell rung while the topic was down is lost, and the server does
    // not ring it again. A member list read while the server was unreachable
    // stayed empty after it came back, until a restart (Oct 26 2026: a server
    // hung for two hours, and Rift was restarted in the middle of it).
    test('opening again after timing out rings once', () async {
      report(RealtimeSubscribeStatus.subscribed);
      report(RealtimeSubscribeStatus.timedOut);
      report(RealtimeSubscribeStatus.channelError);
      report(RealtimeSubscribeStatus.subscribed);
      await settle();
      expect(rings, 1);

      report(RealtimeSubscribeStatus.subscribed);
      await settle();
      expect(rings, 1);
    });

    test('a first join that only opened after failing rings once', () async {
      report(RealtimeSubscribeStatus.timedOut);
      report(RealtimeSubscribeStatus.subscribed);
      await settle();
      expect(rings, 1);
    });
  });

  test(
    'a watcher does not call back from inside its own constructor',
    () async {
      final session = SessionRepository();
      final serverCubit = _cubitWithSelectedServer(session);

      // Building this used to take the app down on launch. The watcher's
      // constructor announced the already-selected server there and then, the
      // cubit refreshed in response, and the refresh read the `_watcher` field
      // that this very constructor call was still in the middle of assigning —
      // an unhandled LateInitializationError, before the first frame.
      final members = ServerMembersCubit(session: session, serverId: 'srv-1');

      // Deferred, not dropped — the server still arrives, a microtask later.
      expect(members.state.serverId, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(members.state.serverId, 'srv-1');

      await members.close();
      await serverCubit.close();
      await session.dispose();
    },
  );
}
