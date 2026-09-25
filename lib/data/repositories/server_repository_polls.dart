part of 'server_repository.dart';

/// Voting on, counting and closing polls. Posting one is an ordinary message
/// send carrying the rules (`sendMessage(poll:)`).
///
/// Every answer here is counts: how many picked each option, how many people
/// voted, and which options the caller picked. The server never says who else
/// voted for what, and the votes table shows each member only their own rows.
mixin _PollApiMixin {
  ServerDb get _db;

  /// Tallies for the polls among [messageIds] — `{tallies: {id: {...}}}`.
  /// Messages that are not polls, or not the caller's to see, are absent.
  Future<APIResponse> pollTallies(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required List<int> messageIds,
  }) {
    return ServerDb.run(() async {
      if (messageIds.isEmpty) return {'tallies': <String, dynamic>{}};
      final tallies = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc('poll_tallies', params: {'p_ids': messageIds});
      return {'tallies': (tallies as Map?)?.cast<String, dynamic>() ?? {}};
    });
  }

  /// Replace the caller's ballot with [options] — empty takes the vote back.
  /// Answers with the new tally.
  Future<APIResponse> votePoll(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int messageId,
    required List<int> options,
  }) {
    return ServerDb.run(() async {
      return await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'vote_poll',
            params: {'p_message': messageId, 'p_options': options},
          );
    });
  }

  /// End a poll now. Its author only.
  Future<APIResponse> closePoll(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int messageId,
  }) {
    return ServerDb.run(() async {
      await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc('close_poll', params: {'p_message': messageId});
      return null;
    });
  }
}
