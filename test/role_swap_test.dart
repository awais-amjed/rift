import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/apis/roles_api.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/role.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';

/// Self-host 068: moving a role is one `swap_role_positions` request, both
/// roles or neither. A server from before it is written a row at a time, and
/// a second write refused puts the first back.
class _Writes extends ServerRepository {
  _Writes({required this.is068, this.refuseSecond = false});

  final bool is068;
  final bool refuseSecond;
  final List<String> asked = [];

  @override
  Future<APIResponse> swapRolePositions(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String roleA,
    required String roleB,
  }) async {
    asked.add('swap $roleA $roleB');
    return is068
        ? APIResponse.success(const {})
        : APIResponse(success: false, errorCode: 'PGRST202');
  }

  @override
  Future<APIResponse> updateRole(
    String supabaseUrl,
    String roleId, {
    required String anonKey,
    String? bearerToken,
    String? name,
    int? position,
    int? permissions,
    String? color,
    bool clearColor = false,
  }) async {
    asked.add('update $roleId $position');
    if (refuseSecond &&
        asked.where((a) => a.startsWith('update')).length == 2) {
      return APIResponse(success: false, error: 'gone', errorCode: '42501');
    }
    return APIResponse.success({
      'rows': [
        {'id': roleId},
      ],
    });
  }

  @override
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async {
    asked.add('details');
    return APIResponse.error('offline');
  }
}

const _low = Role(id: 'low', name: 'Low', position: 10, permissions: 0);
const _high = Role(id: 'high', name: 'High', position: 20, permissions: 0);

void main() {
  RolesApi apiOn(ServerRepository writes) {
    final session = SessionRepository(servers: writes)
      ..publish(
        servers: [
          Server(
            id: 's1',
            name: 'Test',
            supabaseUrl: 'https://server.invalid',
            token: 't',
          ),
        ],
        selectedServerId: 's1',
      );
    return RolesApi(session.on('s1'));
  }

  test('a move is one swap and one read of the server', () async {
    final writes = _Writes(is068: true);
    final result = await apiOn(writes).swapRoles(_low, _high);
    expect(result.success, isTrue);
    expect(writes.asked, ['swap low high', 'details']);
  });

  test('a server from before it is written a row at a time', () async {
    final writes = _Writes(is068: false);
    final result = await apiOn(writes).swapRoles(_low, _high);
    expect(result.success, isTrue);
    expect(writes.asked, [
      'swap low high',
      'update low 20',
      'details',
      'update high 10',
      'details',
    ]);
  });

  test('there, a second write refused puts the first back', () async {
    final writes = _Writes(is068: false, refuseSecond: true);
    final result = await apiOn(writes).swapRoles(_low, _high);
    expect(result.success, isFalse);
    expect(writes.asked, [
      'swap low high',
      'update low 20',
      'details',
      'update high 10',
      'update low 10',
      'details',
    ]);
  });

  test('a swap refused is put in words', () async {
    // Refused as the server does when one of the two may not move.
    final result = await apiOn(_Refusing()).swapRoles(_low, _high);
    expect(result.success, isFalse);
    expect(result.error, contains('could not be swapped'));
  });
}

class _Refusing extends _Writes {
  _Refusing() : super(is068: true);

  @override
  Future<APIResponse> swapRolePositions(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String roleA,
    required String roleB,
  }) async => APIResponse(
    success: false,
    error: 'not_swapped',
    errorCode: 'not_swapped',
  );
}
