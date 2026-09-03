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
///
/// Only written, never read. Reading every cursor to work out the unread counts
/// was a whole-table fetch of something that grows with the number of
/// conversations, and it answered a question `dm_conversations` now answers per
/// row (central migration 013): the count, and the cursor a read writes back,
/// from the same call so the second can never skip what the first counted.
mixin _CentralDmReadStateMixin {
  SupabaseClient get _client;

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
