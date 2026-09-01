part of 'server_repository.dart';

/// Read cursors, and the badges they drive.
///
/// Its own part rather than living with the message reads next door: those
/// fetch envelopes to decrypt, these move a number forward. They were filed
/// under the voice-token banner, which was neither.
mixin _UnreadApiMixin {
  ServerDb get _db;

  /// Unread counts for every channel and conversation on this server, in one
  /// call: `{channels: {id: n}, dms: {peerId: n}}`.
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
}
