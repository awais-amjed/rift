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
  ///
  /// Through `mark_read` rather than a table upsert, for two reasons. A
  /// PostgREST upsert writes every payload column into the `DO UPDATE` clause,
  /// including the conflict key, which the column-level UPDATE grant does not
  /// cover — it failed with "permission denied for table read_state". And the
  /// RPC takes the `GREATEST` of the old and new cursor, so a late-arriving
  /// call can't walk a conversation back to unread.
  Future<APIResponse> setReadCursor({
    required String peerId,
    required int lastReadId,
  }) async {
    try {
      await _client.rpc(
        'mark_read',
        params: {
          'p_scope': 'dm',
          'p_scope_id': peerId,
          'p_last_read_id': lastReadId,
        },
      );
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
