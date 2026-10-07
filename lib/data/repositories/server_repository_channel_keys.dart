part of 'server_repository.dart';

/// Channel keys: fetching the caller's sealed keys, finding key-distribution
/// work, and posting sealed entries for other members.
mixin _ChannelKeysApiMixin {
  ServerDb get _db;

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  // Edge functions on the service role. They enforce the "current + 1"
  // version race, and the work they hand out is found in the database
  // (`channel_key_work`, `channel_key_state`), where no row limit cuts it short.

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

  /// List every channel where the caller can do key-distribution work.
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

  /// Store sealed keyring entries for [keyVersion].
  ///
  /// [mint] is a new version: it fails with `keyring_conflict` if another
  /// writer got there first. Otherwise the version exists and this heals it,
  /// skipping anybody somebody else sealed meanwhile.
  Future<APIResponse> postChannelKeys(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
    required bool mint,
    ({String ciphertext, String nonce})? link,
  }) {
    return _post(supabaseUrl, 'post_channel_keys', {
      'channel_id': channelId,
      'key_version': keyVersion,
      'entries': entries,
      'mint': mint,
      if (link != null)
        'link': {'ciphertext': link.ciphertext, 'nonce': link.nonce},
    }, bearerToken: bearerToken);
  }

  /// Drop this member's own keyring rows at [versions], which the channel's
  /// links already open from a newer row they keep. An RPC rather than an
  /// edge function: it touches only the caller's rows, and the server checks
  /// the chain is there (`prune_channel_keys`).
  Future<APIResponse> pruneChannelKeys(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required List<int> versions,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'prune_channel_keys',
        params: {'p_channel': channelId, 'p_versions': versions},
      );
    });
  }
}
