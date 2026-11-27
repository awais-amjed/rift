import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/repositories/server_db.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';

/// Deleting a server rings every member's app, the owner's own among them,
/// and the owner's request answers only after the server's first purge pass.
/// Seen live on Nov 27: the ring won, the owner's app re-read the server, found
/// it gone, and told the owner "deleted, or you were removed" while their own
/// delete was still spinning.

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

/// A server whose reads answer "gone" once [gone] is set, and whose delete
/// runs [during] before it answers [deleteReply].
class _DeletingServer extends ServerRepository {
  bool gone = false;
  Future<void> Function()? during;
  APIResponse deleteReply = APIResponse.success(const {});

  @override
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async => gone
      ? APIResponse.error(ServerDb.serverGone)
      : APIResponse.success(const <String, dynamic>{});

  @override
  Future<APIResponse> deleteServer(
    String supabaseUrl, {
    String? bearerToken,
  }) async {
    await during?.call();
    return deleteReply;
  }
}

const _url = 'https://server.invalid';
const _me = {'id': 'u1', 'username': 'ada', 'display_name': 'Ada'};

void main() {
  setUp(() {
    HydratedBloc.storage = _MemoryStorage();
    FlutterSecureStorage.setMockInitialValues({});
  });

  late _DeletingServer repo;
  late SessionRepository session;
  late ServerCubit cubit;

  setUp(() {
    repo = _DeletingServer();
    session = SessionRepository(servers: repo);
    cubit = ServerCubit(session: session);
    cubit.addServer(_url, 'jwt', {
      'server_id': 'srv-1',
      'name': 'Rift HQ',
      'supabase_key': 'anon-key',
      'user': _me,
      'channels': <Map<String, dynamic>>[],
    });
  });

  tearDown(() async {
    await cubit.close();
    await session.dispose();
  });

  test('the owner deleting is not told they were removed', () async {
    // The ring's re-read lands while the delete is still waiting.
    repo.during = () {
      repo.gone = true;
      return cubit.refreshServerDetails(serverId: 'srv-1');
    };

    final result = await cubit.deleteServer(cubit.state.servers.single);

    expect(result.success, isTrue);
    expect(cubit.state.servers, isEmpty);
    expect(cubit.state.notice, isNull);
    expect(cubit.isServerGone(supabaseUrl: _url, id: 'srv-1'), isTrue);
  });

  test('a refused delete keeps the server and takes the note back', () async {
    repo.deleteReply = APIResponse.error('Only the owner can delete a server');

    final result = await cubit.deleteServer(cubit.state.servers.single);

    expect(result.success, isFalse);
    expect(cubit.state.servers, hasLength(1));
    expect(cubit.isServerGone(supabaseUrl: _url, id: 'srv-1'), isFalse);
  });

  test('a member whose server goes is still told', () async {
    repo.gone = true;
    await cubit.refreshServerDetails(serverId: 'srv-1');

    expect(cubit.state.servers, isEmpty);
    expect(cubit.state.notice?.title, 'No longer on Rift HQ');
  });
}
