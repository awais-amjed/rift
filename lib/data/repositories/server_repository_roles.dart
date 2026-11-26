part of 'server_repository.dart';

/// Roles and who holds them.
///
/// All direct table calls. There is no RPC here and there does not need to be:
/// the two delegation rules — you may only touch a role below your own, and
/// you may only grant permissions you hold — are `roles_insert`,
/// `roles_update` and `member_roles_insert`, so a client that skipped this
/// file entirely would be refused by the same rules.
///
/// Which is the point of putting them there rather than here.
mixin _RoleApiMixin {
  ServerDb get _db;

  /// Every role on the server, most senior first.
  ///
  /// Every column rather than a list: `is_owner` is newer than the rest,
  /// and naming it on a server without it refuses the whole read.
  /// `Role.fromJson` treats a missing flag as false, which is right.
  Future<APIResponse> listRoles(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('roles')
          .select()
          .order('position', ascending: false);
      return {'roles': rows};
    });
  }

  /// The most rows PostgREST answers with at once in the stack
  /// (`PGRST_DB_MAX_ROWS`), and so the page [listMemberRoles] asks for.
  static const _assignmentPage = 1000;

  /// Who holds what, for the whole server.
  ///
  /// Paged rather than one read: PostgREST cuts any answer at
  /// [_assignmentPage] rows without saying so, and this is one row per
  /// (member, role). Read whole, a server past that counted wrong, and
  /// whoever fell past the cut — the viewer included — read as holding
  /// nothing, which locked every role on their own Roles page. Ordered on the
  /// pair so the pages neither skip nor repeat a row.
  Future<APIResponse> listMemberRoles(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = <Map<String, dynamic>>[];
      while (true) {
        final page = await db
            .from('member_role_list')
            .select(
              'user_id, role_id, name, color, position, permissions, is_owner',
            )
            .order('user_id')
            .order('role_id')
            .range(rows.length, rows.length + _assignmentPage - 1);
        // Until a page comes back empty rather than short: a server set to a
        // lower ceiling than ours cuts every page short.
        if (page.isEmpty) break;
        rows.addAll(page);
      }
      return {'assignments': rows};
    });
  }

  /// How many members hold each role, and the caller's own roles, in one
  /// call (`role_counts`): what the Roles page needs, where
  /// [listMemberRoles] pages through every assignment on the server to work
  /// it out — 49 requests on a server of 50,000 members.
  ///
  /// `counts` is null when the server answers that the caller is no member.
  /// Answers `PGRST202` from a server not updated to have it yet.
  Future<APIResponse> roleCounts(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final row = await db.rpc('role_counts') as Map<String, dynamic>?;
      return {
        'counts': row?['counts'],
        'assignments': row?['mine'] ?? const <Map<String, dynamic>>[],
      };
    });
  }

  Future<APIResponse> createRole(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String serverId,
    required String name,
    required int position,
    required int permissions,
    String? color,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final row = await db
          .from('roles')
          .insert({
            'server_id': serverId,
            'name': name,
            'position': position,
            'permissions': permissions,
            'color': color,
          })
          .select()
          .single();
      return row;
    });
  }

  /// Rename, recolour, reposition, or change what a role carries.
  ///
  /// Answers with the rows changed (`{'rows': [...]}`). A role the caller may
  /// not manage is not an error to PostgREST: `roles_update` filters it out
  /// and the update changes nothing, so an empty list is the refusal.
  ///
  /// `server_id`, `is_everyone` and `legacy_key` are absent from the column
  /// grant, so they are absent here — moving a role to another server or
  /// claiming the baseline is not an edit.
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
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('roles')
          .update({
            'name': ?name,
            'position': ?position,
            'permissions': ?permissions,
            if (clearColor) 'color': null else 'color': ?color,
          })
          .eq('id', roleId)
          .select('id');
      return {'rows': rows};
    });
  }

  /// As [updateRole]: `roles_delete` filters out what the caller may not
  /// delete, so no rows back is the refusal.
  Future<APIResponse> deleteRole(
    String supabaseUrl,
    String roleId, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('roles')
          .delete()
          .eq('id', roleId)
          .select('id');
      return {'rows': rows};
    });
  }

  Future<APIResponse> assignRole(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String roleId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.from('member_roles').insert({
        'user_id': userId,
        'role_id': roleId,
      });
    });
  }

  /// As [updateRole]: `member_roles_delete` filters out what the caller may
  /// not take away, so no rows back is the refusal.
  Future<APIResponse> unassignRole(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String roleId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('member_roles')
          .delete()
          .eq('user_id', userId)
          .eq('role_id', roleId)
          .select('role_id');
      return {'rows': rows};
    });
  }
}
