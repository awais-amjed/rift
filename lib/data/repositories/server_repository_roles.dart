part of 'server_repository.dart';

/// Roles and who holds them (migration 018).
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
  Future<APIResponse> listRoles(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('roles')
          .select(
            'id, name, color, position, permissions, is_everyone, '
            'is_default, is_owner',
          )
          .order('position', ascending: false);
      return {'roles': rows};
    });
  }

  /// Who holds what, for the whole server in one call.
  ///
  /// One query rather than one per member: the members list needs every row of
  /// this to draw a single screen, and a round trip per person is the shape
  /// that works on a test server and falls over on a real one.
  Future<APIResponse> listMemberRoles(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('member_role_list')
          .select(
            'user_id, role_id, name, color, position, permissions, is_default',
          );
      return {'assignments': rows};
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
          .select(
            'id, name, color, position, permissions, is_everyone, '
            'is_default, is_owner',
          )
          .single();
      return row;
    });
  }

  /// Rename, recolour, reposition, or change what a role carries.
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
      return db
          .from('roles')
          .update({
            'name': ?name,
            'position': ?position,
            'permissions': ?permissions,
            if (clearColor) 'color': null else 'color': ?color,
          })
          .eq('id', roleId);
    });
  }

  Future<APIResponse> deleteRole(
    String supabaseUrl,
    String roleId, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.from('roles').delete().eq('id', roleId);
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

  Future<APIResponse> unassignRole(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String roleId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db
          .from('member_roles')
          .delete()
          .eq('user_id', userId)
          .eq('role_id', roleId);
    });
  }
}
