import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/apis/roles_api.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/enums/server_permission.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';

/// Answers each role write with what the test sets.
class _StubServers extends ServerRepository {
  APIResponse answer = APIResponse.success({'rows': <Object>[]});
  int detailReads = 0;

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
  }) async => answer;

  @override
  Future<APIResponse> deleteRole(
    String supabaseUrl,
    String roleId, {
    required String anonKey,
    String? bearerToken,
  }) async => answer;

  @override
  Future<APIResponse> assignRole(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String roleId,
  }) async => answer;

  @override
  Future<APIResponse> unassignRole(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String roleId,
  }) async => answer;

  @override
  Future<APIResponse> createRole(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String serverId,
    required String name,
    required int position,
    required int permissions,
    String? color,
  }) async => answer;

  @override
  Future<APIResponse> memberRolesFor(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required List<String> ids,
  }) async => answer;

  @override
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async {
    detailReads++;
    return APIResponse.error('offline');
  }
}

/// A row policy filters out what the caller may not touch rather than
/// refusing it, so a write to a locked role changed nothing and answered
/// success: the editor closed as though it had saved (review 11, Nov 22).
void main() {
  late _StubServers servers;
  late RolesApi api;

  setUp(() {
    servers = _StubServers();
    final session = SessionRepository(servers: servers)
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
    api = RolesApi(session.on('s1'));
  });

  group('a write the server filtered out is a refusal', () {
    test('editing a role at or above your own', () async {
      final result = await api.updateRole('admin', name: 'Boss');
      expect(result.success, isFalse);
      expect(result.error, contains('at or above your own'));
      expect(servers.detailReads, 0);
    });

    test('deleting one', () async {
      final result = await api.deleteRole('admin');
      expect(result.success, isFalse);
      expect(result.error, contains('at or above your own'));
    });

    test('taking one away', () async {
      final result = await api.setMemberRole(
        userId: 'u2',
        roleId: 'r1',
        held: false,
      );
      expect(result.success, isFalse);
      expect(result.error, contains('cannot take that role away'));
    });

    test('a write that changed its row succeeds', () async {
      servers.answer = APIResponse.success({
        'rows': [
          {'id': 'r1'},
        ],
      });
      final result = await api.updateRole('r1', name: 'Crew');
      expect(result.success, isTrue);
      expect(servers.detailReads, 1);
    });

    test('an assignment answers without rows and succeeds', () async {
      servers.answer = APIResponse.success(null);
      final result = await api.setMemberRole(
        userId: 'u2',
        roleId: 'r1',
        held: true,
      );
      expect(result.success, isTrue);
    });
  });

  group('a refusal is named by its code, not its wording', () {
    Future<String?> createFailing(String code, String message) async {
      servers.answer = APIResponse(
        success: false,
        error: message,
        errorCode: code,
      );
      return (await api.createRole(
        name: 'Moderator',
        position: 1,
        permissions: 0,
      )).error;
    }

    test('a taken name', () async {
      // The unique constraint's message says "violates" too, which once
      // read as a role above your own.
      expect(
        await createFailing(
          '23505',
          'duplicate key value violates unique constraint "roles_server_id_name_key"',
        ),
        'A role with that name already exists',
      );
    });

    test('a name too long', () async {
      expect(
        await createFailing(
          '23514',
          'new row for relation "roles" violates check constraint',
        ),
        contains('1 to 40 characters'),
      );
    });

    test('a role above your own', () async {
      expect(
        await createFailing(
          '42501',
          'new row violates row-level security policy for table "roles"',
        ),
        contains('at or above your own'),
      );
    });
  });

  test('a failed read of who holds what is no answer', () async {
    servers.answer = APIResponse.error('offline');
    expect(await api.memberRolesFor(['u1']), isNull);
  });

  test('the editor offers no box the server does not read', () {
    final offered = {
      for (final group in PermissionGroup.values)
        ...ServerPermission.inGroup(group),
    };
    expect(
      offered.intersection({
        ServerPermission.manageServer,
        ServerPermission.manageRoles,
        ServerPermission.viewChannel,
        ServerPermission.deafenMembers,
        ServerPermission.moveMembers,
      }),
      isEmpty,
    );
    // Read for time-outs, so it is offered as that.
    expect(offered, contains(ServerPermission.muteMembers));
    expect(ServerPermission.muteMembers.label, 'Time out members');
  });
}
