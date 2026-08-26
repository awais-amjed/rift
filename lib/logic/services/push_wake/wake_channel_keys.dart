part of 'wake_server_reader.dart';

/// Getting a channel key inside the push isolate.
///
/// Its own file because it is the one thing here that is not about *what to
/// say*: the isolate holds nothing between wakes, so every notification that
/// needs plaintext starts by re-deriving an identity and re-fetching a keyring
/// it had ten seconds ago. An unencrypted message (a webhook) skips all of it,
/// which is exactly why the caller decides before coming here.
mixin _WakeChannelKeysMixin {
  CryptoRepository get _crypto;
  ServerRepository get _repo;

  /// The channel key at [keyVersion], unwrapped from this member's keyring
  /// entry. Fetched per channel because the isolate holds nothing between
  /// wakes — there is no ring to consult, only the seed.
  Future<Uint8List?> _channelKey(
    WakeServer server,
    String token,
    ChatIdentity identity, {
    required String channelId,
    required int keyVersion,
  }) async {
    final response = await _repo.getChannelKey(
      server.supabaseUrl,
      bearerToken: token,
      channelId: channelId,
    );
    if (!response.success) return null;
    final entries =
        (response.data as Map<String, dynamic>?)?['my_keys'] as List?;
    if (entries == null) return null;

    for (final entry in entries.cast<Map<String, dynamic>>()) {
      if (entry['key_version'] != keyVersion) continue;
      try {
        return await _crypto.unwrapKey(
          wrapped: WrappedKey.fromJson(entry),
          myKeyPair: identity.keyPair,
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
