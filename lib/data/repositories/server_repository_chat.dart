part of 'server_repository.dart';

/// Chat I/O (E2E messaging — ARCHITECTURE.md §4). The client only ever moves
/// opaque envelopes and sealed keys; all crypto happens in CryptoRepository
/// before and after these calls.
///
/// These are direct table calls now. What used to be an edge function per verb
/// is a policy per verb: `messages_insert` requires `sender_id = auth.uid()`
/// and membership of the channel's server, `messages_update_own` and
/// `dm_messages_delete_own` scope by sender, and a BEFORE trigger stamps the
/// sender and timestamp so a modified client can't post as someone else or
/// backdate. The rules are the same ones the endpoints enforced; they are just
/// written where the rows are.
mixin _ChatApiMixin {
  ServerDb get _db;

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// Publish the caller's X25519 chat public key (idempotent).
  Future<APIResponse> publishChatKey(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String chatPublicKey,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db
          .from('users')
          .update({'chat_public_key': chatPublicKey})
          .eq('id', userId);
      return {'published': true};
    });
  }

  /// Store one E2E message envelope. Returns the server-attested id and time.
  ///
  /// [mentions] and [mentionsAll] ride beside the envelope in the clear, and
  /// are the only part of a message that does. The server cannot open the
  /// envelope, so they are the only way it can tell a message that named
  /// somebody from one that did not — which is what a mentions-only channel
  /// turns on (migration 012, which argues the trade at length). They are
  /// validated there, not trusted: ids that aren't live members are dropped
  /// and the array is capped.
  Future<APIResponse> sendMessage(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required Map<String, dynamic> envelope,
    List<String> mentions = const [],
    bool mentionsAll = false,
    String? toBot,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db
          .from('messages')
          .insert({
            'channel_id': channelId,
            ...envelope,
            'mentions': mentions,
            'mentions_all': mentionsAll,
            // Set only for a `/` command, and the reason the envelope above is
            // unsealed when it is. `messages_insert` refuses the two confusing
            // shapes: plaintext addressed to nobody, and a sealed body
            // addressed to a bot that could never open it (migration 015).
            'to_bot': ?toBot,
          })
          .select('id, created_at, channel_id, sender_id')
          .single();
    });
  }

  /// Press something on a bot's panel (migration 029).
  ///
  /// Not a message, and marked as one that isn't: `is_interaction` keeps the
  /// row out of every view except the presser's own and the bot's, wakes
  /// nobody's phone, and does not count as unread. Pressing skip forty times
  /// leaves the channel looking exactly as it did — which is the whole reason
  /// a panel exists rather than a line of chat per press.
  ///
  /// Signed like a command, because it is attributed: the bot is told who
  /// pressed, and an unverifiable press is one anybody could have sent.
  Future<APIResponse> sendPanelAction(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required Map<String, dynamic> envelope,
    required String toBot,
    required int replyTo,
    required String actionId,
    String? actionValue,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.from('messages').insert({
        'channel_id': channelId,
        ...envelope,
        'to_bot': toBot,
        'reply_to': replyTo,
        'is_interaction': true,
        'action_id': actionId,
        'action_value': ?actionValue,
      });
    });
  }

  /// Replace one channel message's envelope in place (sender only).
  Future<APIResponse> editMessage(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int messageId,
    required Map<String, dynamic> envelope,
  }) => _editEnvelope(
    supabaseUrl,
    anonKey: anonKey,
    bearerToken: bearerToken,
    table: 'messages',
    messageId: messageId,
    envelope: envelope,
  );

  /// Replace one server-DM envelope in place (sender only).
  Future<APIResponse> editDm(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int messageId,
    required Map<String, dynamic> envelope,
  }) => _editEnvelope(
    supabaseUrl,
    anonKey: anonKey,
    bearerToken: bearerToken,
    table: 'dm_messages',
    messageId: messageId,
    envelope: envelope,
  );

  Future<APIResponse> _editEnvelope(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String table,
    required int messageId,
    required Map<String, dynamic> envelope,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from(table)
          .update({
            'ciphertext': envelope['ciphertext'],
            'nonce': envelope['nonce'],
            'signature': envelope['signature'],
            'key_version': envelope['key_version'],
          })
          .eq('id', messageId)
          .select('id, edited_at');
      if ((rows as List).isEmpty) {
        // The policy matched no row. "Not found" and "not yours" deliberately
        // look identical — which it was is not the editor's business.
        throw const PostgrestException(
          message: 'Message not found, or not yours to change',
        );
      }
      return rows.first;
    });
  }

  /// Hard-delete one channel message (sender, or a moderator).
  Future<APIResponse> deleteMessage(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int messageId,
  }) => _deleteRow(
    supabaseUrl,
    anonKey: anonKey,
    bearerToken: bearerToken,
    table: 'messages',
    messageId: messageId,
  );

  /// Hard-delete one server DM (sender only; removes it for both sides).
  Future<APIResponse> deleteDm(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int messageId,
  }) => _deleteRow(
    supabaseUrl,
    anonKey: anonKey,
    bearerToken: bearerToken,
    table: 'dm_messages',
    messageId: messageId,
  );

  Future<APIResponse> _deleteRow(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String table,
    required int messageId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from(table)
          .delete()
          .eq('id', messageId)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const PostgrestException(
          message: 'Message not found, or not yours to delete',
        );
      }
      return rows.first;
    });
  }

  /// Store one E2E direct-message envelope for [recipientId].
  Future<APIResponse> sendDm(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db
          .from('dm_messages')
          .insert({'recipient_id': recipientId, ...envelope})
          .select('id, created_at, sender_id, recipient_id')
          .single();
    });
  }

  /// One entry per peer with their identity material and the latest envelope.
  /// `DISTINCT ON` in the database instead of a thousand rows grouped here.
  Future<APIResponse> listDmConversations(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db.rpc('dm_conversations');
      return {'conversations': rows};
    });
  }

  // ──────────────────────────────────────────────────────────
  // Channel keys
  // ──────────────────────────────────────────────────────────
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
