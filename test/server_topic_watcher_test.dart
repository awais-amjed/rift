import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';

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
ServerCubit _cubitWithSelectedServer(SessionRepository session) {
  final cubit = ServerCubit(session: session);
  cubit.addServer('https://server.invalid', 'jwt', {
    'server_id': 'srv-1',
    'name': 'Rift HQ',
    'supabase_key': 'anon-key',
    'user': {'id': 'u1', 'username': 'ada', 'display_name': 'Ada'},
    'channels': <Map<String, dynamic>>[],
  });
  return cubit;
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

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
      final members = ServerMembersCubit(session: session);

      // Deferred, not dropped — the selection still arrives, a microtask later.
      expect(members.state.serverId, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(members.state.serverId, 'srv-1');

      await members.close();
      await serverCubit.close();
      await session.dispose();
    },
  );
}
