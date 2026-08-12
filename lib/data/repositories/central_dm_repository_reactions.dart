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
          .from('dm_message_reactions')
          .select('message_id')
          .eq('message_id', messageId)
          .eq('user_id', uid)
          .eq('emoji', emoji)
          .maybeSingle();

      if (existing != null) {
        await _client
            .from('dm_message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', uid)
            .eq('emoji', emoji);
        return APIResponse.success({'reacted': false});
      }
      await _client.from('dm_message_reactions').insert({
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
  /// `listReactions` (`{ reactions: { id: [{emoji,count,mine}] } }`).
  ///
  /// Message pages carry their own reactions, so this is only for reconciling
  /// after a toggle.
  Future<APIResponse> listReactions({required List<int> messageIds}) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (messageIds.isEmpty || uid == null) {
        return APIResponse.success({'reactions': {}});
      }
      final rows = await _client
          .from('dm_message_reactions')
          .select('message_id, user_id, emoji')
          .inFilter('message_id', messageIds);

      return APIResponse.success({
        'reactions': ReactionOps.byMessage(
          (rows as List).cast<Map<String, dynamic>>(),
          userId: uid,
        ),
      });
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
