import '../../logic/services/role_ladder.dart';
import '../classes/api_response.dart';
import '../classes/role.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Roles for [serverId], or for the selected server. Named because the roles
/// page opens for any server on the rail, not only the one on screen.
///
/// Nothing here is kept. The roles and who holds them are kept by
/// `ServerMembersCubit`, which every screen showing them reads, and which the
/// `members` doorbell keeps current. The one thing the server list holds is
/// the caller's own permission bits, which ride along on the user row with
/// everything else about them — so every write re-reads the server before it
/// answers.
///
/// The delegation rules are not repeated here. They are `roles_insert`,
/// `roles_update` and `member_roles_insert`, and a refusal comes back as an
/// error like any other — which is the right shape: a client that got the rule
/// slightly wrong would otherwise disagree with the database quietly.
///
/// Holds nothing, so a widget builds one from the session.
class RolesApi {
  final SessionRepository _session;

  RolesApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// Every role on this server, most senior first.
  Future<List<Role>> listRoles({String? serverId}) async {
    final server = _session.target(serverId);
    if (server == null) return const [];

    final response = await _session.callFor(
      server,
      (token) => _repository.listRoles(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (!response.success) return const [];

    final rows =
        (response.data as Map<String, dynamic>)['roles'] as List? ?? const [];
    return [
      for (final r in rows.cast<Map<String, dynamic>>()) Role.fromJson(r),
    ];
  }

  /// Who holds what, as `{userId: [role, ...]}`, for the whole server. Null
  /// when the read failed, which is not the same answer as nobody holding
  /// anything.
  Future<Map<String, List<Role>>?> listMemberRoles({String? serverId}) async {
    final server = _session.target(serverId);
    if (server == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _repository.listMemberRoles(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (!response.success) return null;

    return RoleLadder.byUser(_assignmentRows(response));
  }

  /// The roles held by [userIds] and nobody else — the chips for the rows on
  /// screen.
  ///
  /// [listMemberRoles] reads the whole server, which is one row per (member,
  /// role) and so hits the response ceiling sooner than the roster itself does.
  /// It is still the right call for a screen that shows everyone at once; this
  /// is the one for a list that pages.
  Future<Map<String, List<Role>>> memberRolesFor(
    List<String> userIds, {
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null || userIds.isEmpty) return const {};

    final response = await _session.callFor(
      server,
      (token) => _repository.memberRolesFor(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        ids: userIds,
      ),
    );
    if (!response.success) return const {};
    return RoleLadder.byUser(_assignmentRows(response));
  }

  /// The flat `member_role_list` rows out of either call's envelope.
  List<Map<String, dynamic>> _assignmentRows(APIResponse response) =>
      ((response.data as Map<String, dynamic>)['assignments'] as List? ??
              const [])
          .cast<Map<String, dynamic>>();

  /// Mint a role. [position] is the caller's problem, because it is the whole
  /// of the delegation rule — a role at or above your own rank is refused.
  Future<({Role? role, String? error})> createRole({
    required String name,
    required int position,
    required int permissions,
    String? color,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (role: null, error: _session.noTarget(serverId));

    final response = await _session.callFor(
      server,
      (token) => _repository.createRole(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        serverId: server.id,
        name: name,
        position: position,
        permissions: permissions,
        color: color,
      ),
    );
    if (!response.success) {
      return (role: null, error: _roleFailure(response.error));
    }
    return (
      role: Role.fromJson(response.data as Map<String, dynamic>),
      error: null,
    );
  }

  Future<({bool success, String? error})> updateRole(
    String roleId, {
    String? name,
    int? position,
    int? permissions,
    String? color,
    bool clearColor = false,
    String? serverId,
  }) => _changeRole(
    serverId,
    (server, token) => _repository.updateRole(
      server.supabaseUrl,
      roleId,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      name: name,
      position: position,
      permissions: permissions,
      color: color,
      clearColor: clearColor,
    ),
  );

  Future<({bool success, String? error})> deleteRole(
    String roleId, {
    String? serverId,
  }) => _changeRole(
    serverId,
    (server, token) => _repository.deleteRole(
      server.supabaseUrl,
      roleId,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
  );

  Future<({bool success, String? error})> setMemberRole({
    required String userId,
    required String roleId,
    required bool held,
    String? serverId,
  }) => _changeRole(
    serverId,
    (server, token) => held
        ? _repository.assignRole(
            server.supabaseUrl,
            anonKey: server.supabaseKey ?? '',
            bearerToken: token,
            userId: userId,
            roleId: roleId,
          )
        : _repository.unassignRole(
            server.supabaseUrl,
            anonKey: server.supabaseKey ?? '',
            bearerToken: token,
            userId: userId,
            roleId: roleId,
          ),
  );

  /// Every role write ends the same way: the three cached booleans on `users`
  /// have moved, and this device's own copy of its permissions with them.
  Future<({bool success, String? error})> _changeRole(
    String? serverId,
    Future<APIResponse> Function(Server server, String token) call,
  ) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (success: false, error: _session.noTarget(serverId));
    }

    final response = await _session.callFor(
      server,
      (token) => call(server, token),
    );
    if (!response.success) {
      return (success: false, error: _roleFailure(response.error));
    }

    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  /// The database refuses in two ways worth naming, and both read as
  /// gibberish otherwise. Everything else is passed through, because a
  /// message invented here would be a guess about what went wrong.
  static String _roleFailure(String? error) {
    final raw = error ?? 'Could not save that role';
    final lower = raw.toLowerCase();
    if (lower.contains('row-level security') || lower.contains('violates')) {
      return 'That role is at or above your own, or carries something you do '
          'not hold yourself.';
    }
    if (lower.contains('duplicate') || lower.contains('unique')) {
      return 'A role with that name already exists';
    }
    return raw;
  }
}
