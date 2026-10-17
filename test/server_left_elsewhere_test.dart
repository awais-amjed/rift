import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/server_details.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';

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

const _me = {'id': 'u1', 'username': 'ada', 'display_name': 'Ada'};

/// A server left on one device is still in the rail on the others, and in the
/// cloud backup. Its answer to them is our own row, kicked by our own hand;
/// drawn as a kick it read "You were removed", and the backup's copy kept
/// bringing it back.
void main() {
  setUp(() {
    HydratedBloc.storage = _MemoryStorage();
    // Forgetting a server also forgets its saved conversations, which reads
    // the seed first.
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a server our row says we left is dropped and noted gone', () async {
    final session = SessionRepository();
    final cubit = ServerCubit(session: session);
    cubit.addServer('https://server.invalid', 'jwt', {
      'server_id': 'srv-1',
      'name': 'Rift HQ',
      'supabase_key': 'anon-key',
      'user': _me,
      'channels': <Map<String, dynamic>>[],
    });

    cubit.applyServerDetails(
      'srv-1',
      ServerDetails.fromJson({
        'user': {
          ..._me,
          'is_banned': true,
          'is_kicked': true,
          'has_left': true,
        },
        'channels': <Map<String, dynamic>>[],
      }),
    );

    expect(cubit.state.servers, isEmpty);
    expect(
      cubit.isServerGone(supabaseUrl: 'https://server.invalid', id: 'srv-1'),
      isTrue,
    );
    expect(cubit.state.notice?.title, 'You left Rift HQ');

    await cubit.close();
    await session.dispose();
  });

  test('a kick that was not our own still shows the server shut', () async {
    final session = SessionRepository();
    final cubit = ServerCubit(session: session);
    cubit.addServer('https://server.invalid', 'jwt', {
      'server_id': 'srv-1',
      'name': 'Rift HQ',
      'supabase_key': 'anon-key',
      'user': _me,
      'channels': <Map<String, dynamic>>[],
    });

    cubit.applyServerDetails(
      'srv-1',
      ServerDetails.fromJson({
        'user': {..._me, 'is_banned': true, 'is_kicked': true},
        'channels': <Map<String, dynamic>>[],
      }),
    );

    expect(cubit.state.servers.single.user?.isKicked, isTrue);

    await cubit.close();
    await session.dispose();
  });
}
