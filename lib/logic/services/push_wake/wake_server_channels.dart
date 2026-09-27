part of 'wake_server_reader.dart';

/// The channel half of a wake: what arrived in rooms this member is in.
///
/// A channel key is fetched per channel rather than kept, because the isolate
/// keeps nothing between wakes — there is no ring to consult, only the seed
/// and whatever the server will hand back to the identity it derives.
mixin _WakeChannelsMixin on _WakeChannelKeysMixin {
  Future<ChatIdentity?> _chatIdentity(WakeServer server, Uint8List seed);

  /// How far back a mentions-only channel is read before giving up.
  ///
  /// One message is enough at [NotificationLevel.all], where the newest is
  /// always the thing to talk about. It is not enough at
  /// [NotificationLevel.mentions]: the server rang because *some* message
  /// named this member, and three more can land in the time it takes a phone
  /// to wake up — so the one that named them may no longer be the newest.
  /// Reading a few back is the difference between showing that mention and
  /// showing nothing at all.
  static const mentionScanDepth = 10;

  Future<List<WakeItem>> _channelItems(
    WakeServer server,
    Uint8List seed,
    WakeMarks marks,
    String token,
    Map<String, int> unread,
    Map<String, NotificationLevel> levels,
    NotificationLevel? serverLevel,
  ) async {
    if (unread.isEmpty) return const [];
    final identity = await _chatIdentity(server, seed);
    if (identity == null) return const [];

    final items = <WakeItem>[];
    for (final entry in unread.entries) {
      if (items.length >= WakeServerReader.maxScopes) break;

      final level = NotificationLevel.resolve(
        scope: levels[entry.key],
        server: serverLevel,
        fallback: NotificationLevel.channelDefault,
      );
      // A muted channel is still unread and still badged — it just does not
      // get to wake anybody. Skipping it here rather than at the server as
      // well is belt and braces: the ring trigger already refuses, and a wake
      // caused by some *other* channel must not smuggle this one in with it.
      if (level == NotificationLevel.none) continue;

      final item = await _channelItem(
        server,
        marks,
        token,
        identity,
        channelId: entry.key,
        unread: entry.value,
        level: level,
      );
      if (item != null) items.add(item);
    }
    return items;
  }

  /// The newest message in one channel worth saying something about.
  ///
  /// At [NotificationLevel.mentions] that is the newest one that actually
  /// names this member — decided from the *plaintext*, never from the
  /// `mentions` column the sender wrote. The column is what got the phone
  /// woken; it is not evidence, and a client that lied about it buys a silent
  /// wake and nothing else.
  Future<WakeItem?> _channelItem(
    WakeServer server,
    WakeMarks marks,
    String token,
    ChatIdentity identity, {
    required String channelId,
    required int unread,
    required NotificationLevel level,
  }) async {
    final scope = 'channel:${server.id}:$channelId';
    final response = await _repo.listMessages(
      server.supabaseUrl,
      anonKey: server.anonKey,
      userId: server.userId,
      bearerToken: token,
      channelId: channelId,
      limit: level == NotificationLevel.mentions ? mentionScanDepth : 1,
    );
    final rows = WakeServerReader.messagesOf(response);
    final mentionable = Mentions.mentionableFor(server.username);
    final keys = <int, Uint8List>{};

    // Newest first. A row already announced ends the scan rather than skipping
    // it: everything behind it was announced too.
    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null || !marks.isFresh(scope, id)) break;

      final keyVersion = row['key_version'] as int?;
      if (keyVersion == null) continue;

      // An unencrypted row (a webhook) has no key to fetch and
      // no signature to verify, so the whole block below would look up key
      // version 0, fail, and `continue`. Left like that the phone would be
      // woken by the ring trigger and then find nothing to say — the one
      // outcome the wake path exists to avoid.
      if (keyVersion == 0) {
        final item = _plainItem(
          row,
          server,
          scope: scope,
          channelId: channelId,
          messageId: id,
          unread: unread,
          level: level,
        );
        if (item != null) return item;
        continue;
      }

      // Cached across the scan, because a mentions-only channel reads several
      // rows and they are almost always at the same key version — fetching the
      // keyring once per row would turn one round trip into ten. An empty
      // entry is a version already tried and failed, so it is not retried
      // either.
      var key = keys[keyVersion];
      if (key == null) {
        key =
            await _channelKey(
              server,
              token,
              identity,
              channelId: channelId,
              keyVersion: keyVersion,
            ) ??
            Uint8List(0);
        keys[keyVersion] = key;
      }
      if (key.isEmpty) continue;

      final text = await openWakeEnvelope(
        _crypto,
        row,
        key: key,
        contextId: channelId,
      );
      if (text == null) continue;

      final notice = ChatNotice.channel(
        author: row['sender_name'] as String? ?? 'Someone',
        channel: server.channels[channelId] ?? 'channel',
        text: text,
        mentionable: mentionable,
        unread: unread,
      );
      if (!level.announces(mentioned: notice.mentioned)) continue;
      return WakeItem(scope: scope, messageId: id, notice: notice);
    }
    return null;
  }

  /// A notification for an unencrypted row, or null if it should stay quiet.
  ///
  /// The text is read straight off the row, which is the one place in this
  /// isolate where that is allowed — and it is allowed because nothing was
  /// sealed: there is no promise here to break.
  ///
  /// It still cannot claim a mention. `validate_message_mentions` empties the
  /// column for a row with no sender, so a webhook cannot name anybody, and
  /// [ChatNotice.channel] is deciding from the plaintext anyway. A
  /// mentions-only channel therefore stays quiet for these, which is the right
  /// answer: an integration posting build results is not somebody calling you.
  WakeItem? _plainItem(
    Map<String, dynamic> row,
    WakeServer server, {
    required String scope,
    required String channelId,
    required int messageId,
    required int unread,
    required NotificationLevel level,
  }) {
    final text = row['ciphertext'] as String?;
    final author = row['origin_name'] as String?;
    if (text == null || author == null) return null;

    final notice = ChatNotice.channel(
      author: author,
      channel: server.channels[channelId] ?? 'channel',
      text: text,
      mentionable: Mentions.mentionableFor(server.username),
      unread: unread,
    );
    if (!level.announces(mentioned: notice.mentioned)) return null;
    return WakeItem(scope: scope, messageId: messageId, notice: notice);
  }
}
