import 'dart:async';

import '../../logic/services/role_ladder.dart';
import '../classes/api_response.dart';
import '../classes/role.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// Roles on one server. The roles page opens for any server on the rail, not
/// only the one on screen.
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
  final ServerSession _target;

  RolesApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Every role on this server, most senior first.
  Future<List<Role>> listRoles() async {
    final server = _target.server;
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
  Future<Map<String, List<Role>>?> listMemberRoles() async {
    final server = _target.server;
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

  /// How many members hold each role (`{roleId: holders}`, a role nobody
  /// holds absent) and who holds what. Null when the read failed.
  ///
  /// The server counts (`role_counts`), and then [held] is the viewer's own
  /// roles alone, which decide how far down the ladder they reach. A server
  /// not updated to count answers `PGRST202`, and every assignment is read
  /// and counted here as before: then [held] is the whole server, and
  /// [whole] says so, since only then is somebody absent from it holding
  /// nothing.
  Future<({Map<String, int> counts, Map<String, List<Role>> held, bool whole})?>
  roleCounts() async {
    final server = _target.server;
    if (server == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _repository.roleCounts(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (response.success) {
      final counts = (response.data as Map<String, dynamic>)['counts'];
      final me = server.user?.id;
      if (counts is! Map<String, dynamic> || me == null) return null;
      return (
        counts: {
          for (final entry in counts.entries)
            entry.key: (entry.value as num).toInt(),
        },
        held: {
          me: RoleLadder.byUser(_assignmentRows(response))[me] ?? const [],
        },
        whole: false,
      );
    }
    if (response.errorCode != 'PGRST202') return null;

    final held = await listMemberRoles();
    if (held == null) return null;
    final counts = <String, int>{};
    for (final roles in held.values) {
      for (final role in roles) {
        counts[role.id] = (counts[role.id] ?? 0) + 1;
      }
    }
    return (counts: counts, held: held, whole: true);
  }

  /// The roles held by [userIds] and nobody else — the chips for the rows on
  /// screen.
  ///
  /// [listMemberRoles] reads the whole server, which is one row per (member,
  /// role) and so hits the response ceiling sooner than the roster itself does.
  /// It is still the right call for a screen that shows everyone at once; this
  /// is the one for a list that pages. Null when the read failed, as for
  /// [listMemberRoles].
  Future<Map<String, List<Role>>?> memberRolesFor(List<String> userIds) async {
    final server = _target.server;
    if (server == null) return null;
    if (userIds.isEmpty) return const {};

    final response = await _session.callFor(
      server,
      (token) => _repository.memberRolesFor(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        ids: userIds,
      ),
    );
    if (!response.success) return null;
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
  }) async {
    final server = _target.server;
    if (server == null) return (role: null, error: ServerSession.gone);

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
      return (role: null, error: _roleFailure(response));
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
  }) => _changeRole(
    refused: _outranked,
    // A name, colour or place changes nothing a call holds.
    affectsCalls: permissions != null,
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

  Future<({bool success, String? error})> deleteRole(String roleId) =>
      _changeRole(
        refused: _outranked,
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
  }) => _changeRole(
    // An assignment the server refuses fails the insert outright; only a
    // removal comes back empty.
    refused: held
        ? null
        : 'You cannot take that role away. It may be at or above your own, '
              'or no longer held.',
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

  static const _outranked =
      'That role is at or above your own, so you cannot change it.';

  /// Every role write ends the same way: the three cached booleans on `users`
  /// have moved, and this device's own copy of its permissions with them.
  ///
  /// [refused] is said when a write that answers with its rows changed none:
  /// a row policy filters out what the caller may not touch rather than
  /// refusing it, and read as success an edit to a locked role closed its
  /// editor as though saved.
  Future<({bool success, String? error})> _changeRole(
    Future<APIResponse> Function(Server server, String token) call, {
    String? refused,
    bool affectsCalls = true,
  }) async {
    final server = _target.server;
    if (server == null) {
      return (success: false, error: ServerSession.gone);
    }

    final response = await _session.callFor(
      server,
      (token) => call(server, token),
    );
    if (!response.success) {
      return (success: false, error: _roleFailure(response));
    }
    final rows = (response.data as Map?)?['rows'] as List?;
    if (refused != null && rows != null && rows.isEmpty) {
      return (success: false, error: refused);
    }

    // A running call heard none of it: a role is a database row, and a call
    // is checked when somebody joins. Not waited on, since the change itself
    // has landed, and a server from before `refresh_calls` answers with an
    // error nobody needs to see.
    if (affectsCalls) {
      unawaited(
        _session.callFor(
          server,
          (token) =>
              _repository.refreshCalls(server.supabaseUrl, bearerToken: token),
        ),
      );
    }

    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  /// The database's refusals worth naming, by their code: each reads as
  /// gibberish otherwise, and matched on the message instead, "violates"
  /// caught the unique and check constraints too, so a taken name was
  /// reported as a role above your own. Everything else is passed through,
  /// because a message invented here would be a guess about what went wrong.
  static String _roleFailure(APIResponse response) {
    final raw = response.error ?? 'Could not save that role';
    return switch (response.errorCode) {
      '42501' =>
        'That role is at or above your own, or carries something you do '
            'not hold yourself.',
      '23505' => 'A role with that name already exists',
      '23514' =>
        'A role needs a name of 1 to ${Role.maxNameLength} characters, and '
            'a position of 0 or more.',
      'owner_is_permanent' => 'The owner role cannot be deleted.',
      'everyone_is_permanent' => 'The @everyone role cannot be deleted.',
      'owner_is_singular' => 'Only one person can hold the owner role.',
      'bot_cannot_own' => 'A bot cannot hold the owner role.',
      _ => raw,
    };
  }
}
