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
    return _post(
      supabaseUrl,
      'publish_chat_key',
      {'chat_public_key': chatPublicKey},
      bearerToken: bearerToken,
    );
  }

  /// Store one E2E message envelope. Returns the server-attested
  /// `id` + `created_at`.
  Future<APIResponse> sendMessage(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    required Map<String, dynamic> envelope,
  }) {
    return _post(
      supabaseUrl,
      'send_message',
      {'channel_id': channelId, ...envelope},
      bearerToken: bearerToken,
    );
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
    return _post(
      supabaseUrl,
      'list_messages',
      {
        'channel_id': channelId,
        'before_id': ?beforeId,
        'after_id': ?afterId,
        'limit': ?limit,
      },
      bearerToken: bearerToken,
    );
  }

  /// Fetch my sealed channel keys + current version + members missing
  /// current-version entries (the healing set).
  Future<APIResponse> getChannelKey(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
  }) {
    return _post(
      supabaseUrl,
      'get_channel_key',
      {'channel_id': channelId},
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
    return _post(
      supabaseUrl,
      'post_channel_keys',
      {
        'channel_id': channelId,
        'key_version': keyVersion,
        'entries': entries,
      },
      bearerToken: bearerToken,
    );
  }
}
