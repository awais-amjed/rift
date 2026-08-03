part of 'central_dm_repository.dart';

/// Reactions on central DMs. **Not end-to-end encrypted** — the central
/// server sees who reacted with which emoji. That is the accepted trade-off
/// recorded in ARCHITECTURE.md §4; message content stays opaque.
///
/// These are direct table operations rather than RPCs; RLS scopes them to
/// conversations the caller is part of.
mixin _CentralDmReactionsMixin {
  SupabaseClient get _client;

  // ──────────────────────────────────────────────────────────
  // Reactions (not E2E — server-visible; RLS-scoped direct table ops)
  // ──────────────────────────────────────────────────────────

  /// Toggle the caller's [emoji] reaction on a central DM message.
  Future<APIResponse> toggleReaction({
    required int messageId,
    required String emoji,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return APIResponse.error('Not signed in');

      final existing = await _client
          .from('dm_reactions')
          .select('message_id')
          .eq('message_id', messageId)
          .eq('user_id', uid)
          .eq('emoji', emoji)
          .maybeSingle();

      if (existing != null) {
        await _client
            .from('dm_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', uid)
            .eq('emoji', emoji);
        return APIResponse.success({'reacted': false});
      }
      await _client.from('dm_reactions').insert({
        'message_id': messageId,
        'user_id': uid,
        'emoji': emoji,
      });
      return APIResponse.success({'reacted': true});
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Aggregated reactions for [messageIds], shaped like the self-hosted
  /// `list_reactions` (`{ reactions: { id: [{emoji,count,mine}] } }`).
  Future<APIResponse> listReactions({required List<int> messageIds}) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (messageIds.isEmpty || uid == null) {
        return APIResponse.success({'reactions': {}});
      }
      final rows = await _client
          .from('dm_reactions')
          .select('message_id, user_id, emoji')
          .inFilter('message_id', messageIds);

      final byMsg = <String, Map<String, Map<String, dynamic>>>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final mid = '${row['message_id']}';
        final emoji = row['emoji'] as String;
        final bucket = byMsg.putIfAbsent(mid, () => {});
        final agg = bucket.putIfAbsent(
          emoji,
          () => {'emoji': emoji, 'count': 0, 'mine': false},
        );
        agg['count'] = (agg['count'] as int) + 1;
        if (row['user_id'] == uid) agg['mine'] = true;
      }
      final reactions = <String, dynamic>{};
      byMsg.forEach((mid, bucket) => reactions[mid] = bucket.values.toList());
      return APIResponse.success({'reactions': reactions});
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
