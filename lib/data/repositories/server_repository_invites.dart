part of 'server_repository.dart';

/// The links into a server, read and revoked from its Invites page.
///
/// Making one, and throwing away one this account just made, are
/// `_AuthApiMixin`'s. These are the list: `invites_select_admin` and
/// `invites_delete_admin` let an administrator reach every link on the
/// server, and a member reaches only their own (`invites_select_own`). On a
/// server from before Nov 22 2026 an administrator too reaches only their own.
mixin _InviteListApiMixin {
  ServerDb get _db;

  /// The server's links, newest first, with who made each one. The code is
  /// read too: revoking goes by id, but the page shows the end of the link so
  /// one pasted somewhere can be told from the others.
  Future<APIResponse> listInvites(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('invites')
          .select(
            'id, code, created_at, created_by, max_uses, uses, expires_at, '
            'is_bot, role_id, '
            'creator:users!invites_created_by_fkey(display_name, username)',
          )
          .order('created_at', ascending: false)
          .limit(ServerRepository.invitesPage);
      return {'invites': (rows as List).cast<Map<String, dynamic>>()};
    });
  }

  /// Revoke one link by id. `deleted` is false when no row went: gone
  /// already, or not the caller's to remove.
  Future<APIResponse> revokeInvite(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String inviteId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('invites')
          .delete()
          .eq('id', inviteId)
          .select('id');
      return {'deleted': (rows as List).isNotEmpty};
    });
  }
}
