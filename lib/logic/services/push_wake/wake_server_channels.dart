part of 'wake_server_reader.dart';

/// The channel half of a wake: what arrived in rooms this member is in.
///
/// A channel key is fetched per channel rather than kept, because the isolate
/// keeps nothing between wakes — there is no ring to consult, only the seed
/// and whatever the server will hand back to the identity it derives.
mixin _WakeChannelsMixin {
  CryptoRepository get _crypto;
  ServerRepository get _repo;
  Future<ChatIdentity?> _chatIdentity(WakeServer server, Uint8List seed);

  Future<List<WakeItem>> _channelItems(
    WakeServer server,
    Uint8List seed,
    WakeMarks marks,
    String token,
    Map<String, int> unread,
  ) async {
    if (unread.isEmpty) return const [];
    final identity = await _chatIdentity(server, seed);
    if (identity == null) return const [];

    final items = <WakeItem>[];
    for (final entry in unread.entries) {
      if (items.length >= WakeServerReader.maxScopes) break;
      final scope = 'channel:${server.id}:${entry.key}';

      final response = await _repo.listMessages(
        server.supabaseUrl,
        anonKey: server.anonKey,
        userId: server.userId,
        bearerToken: token,
        channelId: entry.key,
        limit: 1,
      );
      final row = WakeServerReader.firstMessage(response);
      if (row == null) continue;

      final id = row['id'] as int;
      if (!marks.isFresh(scope, id)) continue;

      final key = await _channelKey(
        server,
        token,
        identity,
        channelId: entry.key,
        keyVersion: row['key_version'] as int,
      );
      if (key == null) continue;

      final text = await openWakeEnvelope(
        _crypto,
        row,
        key: key,
        contextId: entry.key,
      );
      if (text == null) continue;

      items.add(
        WakeItem(
          scope: scope,
          messageId: id,
          notice: ChatNotice.channel(
            author: row['sender_name'] as String? ?? 'Someone',
            channel: server.channels[entry.key] ?? 'channel',
            text: text,
            mentionable: server.username.isEmpty
                ? const {}
                : {server.username.toLowerCase()},
            unread: entry.value,
          ),
        ),
      );
    }
    return items;
  }

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
