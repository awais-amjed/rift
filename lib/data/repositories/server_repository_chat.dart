part of 'server_repository.dart';

/// Chat API calls (E2E messaging — ARCHITECTURE.md §4). The client only ever
/// sends/receives opaque envelopes and sealed keys; all crypto happens in
/// CryptoRepository before/after these calls.
mixin _ChatApiMixin {
  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// Publish the caller's X25519 chat public key (idempotent upsert).
  Future<APIResponse> publishChatKey(
    String supabaseUrl, {
    String? bearerToken,
    required String chatPublicKey,
  }) {
    return _post(supabaseUrl, 'publish_chat_key', {
      'chat_public_key': chatPublicKey,
    }, bearerToken: bearerToken);
  }

  /// Toggle the caller's [emoji] reaction on a message. [scope] is `channel`
  /// (pass [channelId]) or `dm` (pass [peerId]). Returns `{ reacted }`.
  Future<APIResponse> toggleReaction(
    String supabaseUrl, {
    String? bearerToken,
    required String scope,
    String? channelId,
    String? peerId,
    required int messageId,
    required String emoji,
  }) {
    return _post(supabaseUrl, 'toggle_reaction', {
      'scope': scope,
      'channel_id': ?channelId,
      'peer_id': ?peerId,
      'message_id': messageId,
      'emoji': emoji,
    }, bearerToken: bearerToken);
  }

  /// Aggregated reactions for [messageIds] (`{ reactions: { id: [...] } }`).
  Future<APIResponse> listReactions(
    String supabaseUrl, {
    String? bearerToken,
    required String scope,
    String? channelId,
    String? peerId,
    required List<int> messageIds,
  }) {
    return _post(supabaseUrl, 'list_reactions', {
      'scope': scope,
      'channel_id': ?channelId,
      'peer_id': ?peerId,
      'message_ids': messageIds,
    }, bearerToken: bearerToken);
  }

  /// Store one E2E message envelope. Returns the server-attested
  /// `id` + `created_at`.
  Future<APIResponse> sendMessage(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    required Map<String, dynamic> envelope,
  }) {
    return _post(supabaseUrl, 'send_message', {
      'channel_id': channelId,
      ...envelope,
    }, bearerToken: bearerToken);
  }

  /// Page through a channel's envelopes. Pass [beforeId] for history
  /// (newest-first) or [afterId] for live catch-up (oldest-first).
  Future<APIResponse> listMessages(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) {
    return _post(supabaseUrl, 'list_messages', {
      'channel_id': channelId,
      'before_id': ?beforeId,
      'after_id': ?afterId,
      'limit': ?limit,
    }, bearerToken: bearerToken);
  }

  /// Fetch my sealed channel keys + current version + members missing
  /// current-version entries (the healing set).
  Future<APIResponse> getChannelKey(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
  }) {
    return _post(supabaseUrl, 'get_channel_key', {
      'channel_id': channelId,
    }, bearerToken: bearerToken);
  }

  /// List every channel where the caller can do key-distribution work:
  /// version-0 channels to bootstrap, and channels where the caller holds the
  /// current key while other keyed members lack entries.
  Future<APIResponse> sweepChannelKeys(
    String supabaseUrl, {
    String? bearerToken,
  }) {
    return _post(
      supabaseUrl,
      'sweep_channel_keys',
      {},
      bearerToken: bearerToken,
    );
  }

  /// Store one E2E direct-message envelope for [recipientId].
  Future<APIResponse> sendDm(
    String supabaseUrl, {
    String? bearerToken,
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) {
    return _post(supabaseUrl, 'send_dm', {
      'recipient_id': recipientId,
      ...envelope,
    }, bearerToken: bearerToken);
  }

  /// Page through the DM conversation with [peerId].
  Future<APIResponse> listDms(
    String supabaseUrl, {
    String? bearerToken,
    required String peerId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) {
    return _post(supabaseUrl, 'list_dms', {
      'peer_id': peerId,
      'before_id': ?beforeId,
      'after_id': ?afterId,
      'limit': ?limit,
    }, bearerToken: bearerToken);
  }

  /// List DM conversations (one per peer, latest envelope included).
  Future<APIResponse> listDmConversations(
    String supabaseUrl, {
    String? bearerToken,
  }) {
    return _post(
      supabaseUrl,
      'list_dm_conversations',
      {},
      bearerToken: bearerToken,
    );
  }

  /// Store sealed keyring entries for [keyVersion]. Fails with
  /// `keyring_conflict` if another writer won the version race.
  Future<APIResponse> postChannelKeys(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
  }) {
    return _post(supabaseUrl, 'post_channel_keys', {
      'channel_id': channelId,
      'key_version': keyVersion,
      'entries': entries,
    }, bearerToken: bearerToken);
  }
}
