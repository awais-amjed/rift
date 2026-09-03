part of 'server_repository.dart';

/// Reaction I/O on a self-hosted server. **Not end-to-end encrypted** — the
/// server stores one row per person per emoji and can read them, which is the
/// accepted trade-off recorded in ARCHITECTURE.md §4. Message content stays
/// opaque either way.
///
/// Reads come in two shapes and both are needed. A message page carries its own
/// reactions as an embed (see `_ChatApiMixin`), so opening a channel is one
/// round trip; [listReactions] answers separately for the doorbell path, where
/// someone else's reaction must not cost a re-download and re-decrypt of fifty
/// envelopes.
mixin _ReactionApiMixin {
  ServerDb get _db;

  /// Which table a [scope] of `channel` or `dm` means.
  static String _tableFor(String scope) =>
      scope == 'dm' ? 'dm_message_reactions' : 'message_reactions';

  /// Toggle the caller's [emoji] reaction on a message. Returns `{reacted}`.
  ///
  /// Insert-then-fall-back-to-delete rather than read-then-write: the primary
  /// key is (message, user, emoji), so a duplicate is the database telling us
  /// the reaction was already there, with no window in between.
  Future<APIResponse> toggleReaction(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String scope,
    required int messageId,
    required String emoji,
  }) {
    final table = _tableFor(scope);
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      try {
        await db.from(table).insert({
          'message_id': messageId,
          'user_id': userId,
          'emoji': emoji,
        });
        return {'reacted': true};
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
        await db
            .from(table)
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', userId)
            .eq('emoji', emoji);
        return {'reacted': false};
      }
    });
  }

  /// Aggregated reactions for [messageIds] — `{reactions: {id: [...]}}` with a
  /// count and whether the caller is in it.
  ///
  /// Usually one id: a reaction doorbell names the message that changed. The
  /// batch form remains for the fallback path, where a client rang without
  /// saying which.
  ///
  /// Counted by the database (migration 040) rather than here. This used to ask
  /// for one row per person per emoji across the whole batch, and PostgREST
  /// caps a response at 1000 rows — fifty messages with twenty reactors each is
  /// a lively channel, not an extreme one, and past that point the answer was
  /// trimmed and the counts quietly read low. The tally is one row per
  /// (message, emoji) and comes back as a scalar, so there is nothing left to
  /// truncate.
  ///
  /// [userId] is no longer used to decide what is "mine" — the database knows
  /// who is asking. It stays in the signature because both call sites have it
  /// and a parameter is cheaper than two shapes of the same call.
  Future<APIResponse> listReactions(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String scope,
    required List<int> messageIds,
  }) {
    return ServerDb.run(() async {
      if (messageIds.isEmpty) return {'reactions': <String, dynamic>{}};
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final tallies = await db.rpc(
        'message_reaction_tallies',
        params: {'p_scope': scope, 'p_ids': messageIds},
      );
      return {'reactions': (tallies as Map?)?.cast<String, dynamic>() ?? {}};
    });
  }
}
