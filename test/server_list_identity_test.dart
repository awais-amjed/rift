import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/services/backup_merge.dart';

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

const _here = 'https://rift.example';
const _elsewhere = 'https://impostor.example';

Map<String, dynamic> _joined(String id, String name) => {
  'server_id': id,
  'name': name,
  'supabase_key': 'anon-key',
  'user': {'id': 'u1', 'username': 'ada', 'display_name': 'Ada'},
  'channels': <Map<String, dynamic>>[],
};

/// A server picks its own id, and the app finds a server by its id alone:
/// its token, its socket and its removal all follow the id. So the list holds
/// one row per id, whatever a server answers or a merge brings.
void main() {
  late SessionRepository session;
  late ServerCubit cubit;

  setUp(() {
    HydratedBloc.storage = _MemoryStorage();
    FlutterSecureStorage.setMockInitialValues({});
    session = SessionRepository();
    cubit = ServerCubit(session: session);
  });

  tearDown(() async {
    await cubit.close();
    await session.dispose();
  });

  test('a server answering with the id of one on the list is not added', () {
    cubit.addServer(_here, 'jwt-a', _joined('s1', 'Rift HQ'));

    final added = cubit.addServer(_elsewhere, 'jwt-b', _joined('s1', 'Evil'));

    expect(added, isNull);
    expect(cubit.state.servers.map((s) => s.name), ['Rift HQ']);
    expect(cubit.state.servers.single.token, 'jwt-a');
    expect(cubit.state.notice?.message, contains('rift.example'));
  });

  test('joining a server already on the list takes its place', () {
    cubit.addServer(_here, 'jwt-a', _joined('s1', 'Rift HQ'));
    cubit.addServer(_here, 'jwt-x', _joined('s2', 'Other'));

    // An invite tapped again, pasted with a trailing slash.
    final added = cubit.addServer('$_here/', 'jwt-b', _joined('s1', 'Rift'));

    expect(added, isNotNull);
    expect(cubit.state.servers.map((s) => s.id), ['s1', 's2']);
    expect(cubit.state.servers.first.token, 'jwt-b');
    expect(cubit.state.servers.first.supabaseUrl, _here);
    expect(cubit.state.selectedServerId, 's1');
  });

  test('a cloud copy of an id held at another address is not added', () {
    cubit.addServer(_here, 'jwt-a', _joined('s1', 'Rift HQ'));

    cubit.mergeCloudManifest(
      const ServerManifest(
        servers: [
          {'id': 's1', 'name': 'Evil', 'supabaseUrl': _elsewhere},
          {'id': 's9', 'name': 'New', 'supabaseUrl': _here},
          {'id': 's9', 'name': 'Twice', 'supabaseUrl': _elsewhere},
        ],
        orderClock: 0,
      ),
    );

    expect(cubit.state.servers.map((s) => (s.id, s.supabaseUrl)), [
      ('s1', _here),
      ('s9', _here),
    ]);
  });

  test('a server being left keeps its place through a merge', () {
    cubit.addServer(_here, 'jwt-a', _joined('s1', 'First'));
    cubit.addServer(_here, 'jwt-b', _joined('s2', 'Second'));
    final manifest = cubit.getServersForExport();

    // The leave is still waiting on the server when the cloud's copy lands.
    cubit.noteServerGone(supabaseUrl: _here, id: 's1');
    cubit.mergeCloudManifest(manifest);

    expect(cubit.state.servers.map((s) => s.id), ['s1', 's2']);
  });
}
