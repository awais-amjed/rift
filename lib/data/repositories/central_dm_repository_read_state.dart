part of 'central_dm_repository.dart';

/// The `read_state` table: one row per conversation holding the newest
/// message id the caller has read.
///
/// It lives on the server rather than in local storage so that reading a
/// conversation on one device leaves it read on the others. RLS is own-row
/// (`user_id = auth.uid()`), so a cursor is private to the person it belongs
/// to; nobody learns whether their message was read.
///
/// The same table, with the same `scope`/`scope_id` shape, is what a
/// self-hosted server uses for both channels and DMs.
mixin _CentralDmReadStateMixin {
  SupabaseClient get _client;

  /// Every conversation's cursor for the caller: `{peerId: lastReadId}`.
  Future<APIResponse> listReadCursors() async {
    try {
      final rows = await _client
          .from('read_state')
          .select('scope_id, last_read_id')
          .eq('user_id', _client.auth.currentUser!.id)
          .eq('scope', 'dm');
      final cursors = <String, int>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final peerId = row['scope_id'] as String?;
        final lastRead = row['last_read_id'];
        if (peerId != null && lastRead is int) cursors[peerId] = lastRead;
      }
      return APIResponse.success(cursors);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Move one conversation's cursor to [lastReadId].
  Future<APIResponse> setReadCursor({
    required String peerId,
    required int lastReadId,
  }) async {
    try {
      await _client.from('read_state').upsert({
        'user_id': _client.auth.currentUser!.id,
        'scope': 'dm',
        'scope_id': peerId,
        'last_read_id': lastReadId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        // No space: this goes on the query string as a column list, and a
        // stray one is looked up as part of the second column's name.
      }, onConflict: 'user_id,scope,scope_id');
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
