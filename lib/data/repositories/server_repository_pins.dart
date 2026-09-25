part of 'server_repository.dart';

/// Pins on a self-hosted server, for channels and server DMs alike.
///
/// **Not end-to-end encrypted**, like reactions: the server knows which
/// messages are pinned and who pinned them, never what they say. Pinning is
/// one RPC, `set_pinned`, which holds the fifty-a-conversation cap and the
/// `PIN_MESSAGES` check; listing is a plain read with the message embedded,
/// under the same policies as reading it anywhere else.
mixin _PinApiMixin {
  ServerDb get _db;

  /// Pin or unpin a message. [scope] is `channel` or `dm`.
  Future<APIResponse> setPinned(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String scope,
    required int messageId,
    required bool pinned,
  }) {
    return ServerDb.run(() async {
      await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'set_pinned',
            params: {
              'p_scope': scope,
              'p_message': messageId,
              'p_pinned': pinned,
            },
          );
      return null;
    });
  }

  /// A channel's pins, newest pin first, as message rows in the shape a page
  /// of history comes in — `{messages: [...]}` — so the cubit decrypts them
  /// with the same code.
  Future<APIResponse> listChannelPins(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
  }) {
    return ServerDb.run(() async {
      final rows = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('message_pins')
          .select(
            'pinned_at, messages!inner(${_ChatReadApiMixin._messageColumns})',
          )
          .eq('channel_id', channelId)
          .order('pinned_at', ascending: false)
          .limit(50);
      return {
        'messages': [
          for (final row in (rows as List).cast<Map<String, dynamic>>())
            _ChatReadApiMixin._flatten(
              (row['messages'] as Map).cast<String, dynamic>(),
              userId: userId,
              reactionsKey: 'message_reactions',
            ),
        ],
      };
    });
  }

  /// The pins of the DM between [userId] and [peerId], newest pin first.
  Future<APIResponse> listDmPins(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String peerId,
  }) {
    // The table keeps the pair sorted, so either side asks the same question.
    final pair = [userId, peerId]..sort();
    return ServerDb.run(() async {
      final rows = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('dm_message_pins')
          .select(
            'pinned_at, dm_messages!inner(${_ChatReadApiMixin._dmColumns})',
          )
          .eq('user_low', pair.first)
          .eq('user_high', pair.last)
          .order('pinned_at', ascending: false)
          .limit(50);
      return {
        'messages': [
          for (final row in (rows as List).cast<Map<String, dynamic>>())
            _ChatReadApiMixin._flatten(
              (row['dm_messages'] as Map).cast<String, dynamic>(),
              userId: userId,
              reactionsKey: 'dm_message_reactions',
            ),
        ],
      };
    });
  }
}
