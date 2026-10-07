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
    final data = response.data as Map<String, dynamic>?;
    final entries = (data?['my_keys'] as List?)?.cast<Map<String, dynamic>>();
    if (entries == null) return null;

    // This member's own row for the version if it has one; otherwise the
    // nearest newer row, and the links down from it — a client drops a row
    // once the chain covers it, and a newcomer was never sealed one.
    final rows = entries
        .where((e) => (e['key_version'] as int) >= keyVersion)
        .toList()
      ..sort(
        (a, b) => (a['key_version'] as int).compareTo(b['key_version'] as int),
      );
    if (rows.isEmpty) return null;
    final Uint8List nearest;
    try {
      nearest = await _crypto.unwrapKey(
        wrapped: WrappedKey.fromJson(rows.first),
        myKeyPair: identity.keyPair,
      );
    } catch (_) {
      return null;
    }
    final keys = {rows.first['key_version'] as int: nearest};
    await ChannelKeyChain.follow(
      crypto: _crypto,
      channelId: channelId,
      keys: keys,
      links: ((data?['links'] as List?) ?? const [])
          .cast<Map<String, dynamic>>(),
    );
    return keys[keyVersion];
  }
}
