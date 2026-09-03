part of 'server_cubit.dart';

/// Roles for the selected server (migration 018).
///
/// Nothing here touches [ServerState]. Roles are read when a dialog opens and
/// thrown away when it closes — there is no badge and no live view that would
/// go stale, so holding them in cubit state would be state kept for its own
/// sake. The one thing that *is* held is the caller's own permission bits, and
/// those ride along on the user row with everything else about them.
///
/// The delegation rules are not repeated here. They are `roles_insert`,
/// `roles_update` and `member_roles_insert`, and a refusal comes back as an
/// error like any other — which is the right shape: a client that got the rule
/// slightly wrong would otherwise disagree with the database quietly.
mixin _ServerRolesApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  String get _anonKey;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Implemented by [_ServerApiMixin]. A role change moves the three cached
  /// booleans on `users`, so the selected server's own user row is stale until
  /// this runs.
  Future<({bool success, String? error})> refreshServerDetails();

  /// Every role on this server, most senior first.
  Future<List<Role>> listRoles() async {
    final server = state.selectedServer;
    if (server == null) return const [];

    final response = await _callWithAutoRefresh(
      (token) => _repository.listRoles(
        server.supabaseUrl,
        anonKey: _anonKey,
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

  /// Who holds what, as `{userId: [roleId, ...]}`.
  Future<Map<String, List<Role>>> listMemberRoles() async {
    final server = state.selectedServer;
    if (server == null) return const {};

    final response = await _callWithAutoRefresh(
      (token) => _repository.listMemberRoles(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
      ),
    );
    if (!response.success) return const {};

    return RoleLadder.byUser(_assignmentRows(response));
  }

  /// The roles held by [userIds] and nobody else — the chips for the rows on
  /// screen.
  ///
  /// [listMemberRoles] reads the whole server, which is one row per (member,
  /// role) and so hits the response ceiling sooner than the roster itself does.
  /// It is still the right call for a screen that shows everyone at once; this
  /// is the one for a list that pages.
  Future<Map<String, List<Role>>> memberRolesFor(List<String> userIds) async {
    final server = state.selectedServer;
    if (server == null || userIds.isEmpty) return const {};

    final response = await _callWithAutoRefresh(
      (token) => _repository.memberRolesFor(
        server.supabaseUrl,
        anonKey: _anonKey,
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
  }) async {
    final server = state.selectedServer;
    if (server == null) return (role: null, error: 'No server selected');

    final response = await _callWithAutoRefresh(
      (token) => _repository.createRole(
        server.supabaseUrl,
        anonKey: _anonKey,
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
  }) => _changeRole(
    (server, token) => _repository.updateRole(
      server.supabaseUrl,
      roleId,
      anonKey: _anonKey,
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
        (server, token) => _repository.deleteRole(
          server.supabaseUrl,
          roleId,
          anonKey: _anonKey,
          bearerToken: token,
        ),
      );

  Future<({bool success, String? error})> setMemberRole({
    required String userId,
    required String roleId,
    required bool held,
  }) => _changeRole(
    (server, token) => held
        ? _repository.assignRole(
            server.supabaseUrl,
            anonKey: _anonKey,
            bearerToken: token,
            userId: userId,
            roleId: roleId,
          )
        : _repository.unassignRole(
            server.supabaseUrl,
            anonKey: _anonKey,
            bearerToken: token,
            userId: userId,
            roleId: roleId,
          ),
  );

  /// Every role write ends the same way: the three cached booleans on `users`
  /// have moved, and this device's own copy of its permissions with them.
  Future<({bool success, String? error})> _changeRole(
    Future<APIResponse> Function(Server server, String token) call,
  ) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server selected');

    final response = await _callWithAutoRefresh((token) => call(server, token));
    if (!response.success) {
      return (success: false, error: _roleFailure(response.error));
    }

    await refreshServerDetails();
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
