part of 'server_repository.dart';

/// Channel keys: fetching the caller's sealed keys, finding key-distribution
/// work, and posting sealed entries for other members.
mixin _ChannelKeysApiMixin {
  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  // Still edge functions. The key-distribution path enforces the "current + 1"
  // version race and computes healing sets across channels; moving it is a
  // careful job of its own, and getting it wrong silently breaks decryption for
  // everyone rather than throwing. It runs on the service role and is unchanged
  // by this migration.

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
