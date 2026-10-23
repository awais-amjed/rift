part of 'server_repository.dart';

/// Read cursors, and the badges they drive — and how much each conversation
/// may interrupt, since the levels ride along with the counts.
///
/// Its own part rather than living with the message reads next door: those
/// fetch envelopes to decrypt, these move a number forward. They were filed
/// under the voice-token banner, which was neither.
mixin _UnreadApiMixin {
  ServerDb get _db;

  /// Unread counts for every channel and conversation on this server, in one
  /// call: `{channels: {id: n}, dms: {peerId: n}, prefs: {...}}`.
  Future<APIResponse> unreadCounts(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc('unread_counts');
    });
  }

  /// Move a read cursor forward. Omit [lastReadId] to mean "everything there
  /// is right now". Never moves backwards, so two devices can't un-read each
  /// other's progress.
  Future<APIResponse> markRead(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String scope,
    required String scopeId,
    int lastReadId = 0,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'mark_read',
        params: {
          'p_scope': scope,
          'p_scope_id': scopeId,
          'p_last_read_id': lastReadId,
        },
      );
    });
  }

  /// Move every cursor on the server to what is newest right now.
  Future<APIResponse> markAllRead(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc('mark_all_read');
    });
  }

  /// Store how much [scope]/[scopeId] may interrupt [userId].
  ///
  /// Straight to `notification_prefs` under its own-row policy. There is no
  /// RPC because there is no rule one would enforce that the policy doesn't:
  /// a member may set their own, and nobody else's.
  Future<APIResponse> setNotificationLevel(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String scope,
    required String scopeId,
    required String level,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db.from('notification_prefs').upsert({
        'user_id': userId,
        'scope': scope,
        'scope_id': scopeId,
        'level': level,
      }, onConflict: 'user_id,scope,scope_id');
      return null;
    });
  }

  /// Drop [userId]'s level for [scope]/[scopeId], so it follows the scope
  /// above it again.
  Future<APIResponse> clearNotificationLevel(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String scope,
    required String scopeId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db
          .from('notification_prefs')
          .delete()
          .eq('user_id', userId)
          .eq('scope', scope)
          .eq('scope_id', scopeId);
      return null;
    });
  }
}
