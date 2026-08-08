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

  /// The columns every message read needs, with the sender's profile embedded.
  /// The FK has to be named explicitly: reactions added a second
  /// messages↔users relationship, and PostgREST refuses an ambiguous embed.
  static const _messageColumns =
      'id, created_at, channel_id, sender_id, ciphertext, nonce, signature, '
      'key_version, edited_at, '
      'sender:users!messages_sender_id_fkey(display_name, public_key, avatar_path)';

  static const _dmColumns =
      'id, created_at, sender_id, recipient_id, ciphertext, nonce, signature, '
      'key_version, edited_at, '
      'sender:users!dm_messages_sender_id_fkey(display_name, public_key, avatar_path)';

  /// Lifts the embedded sender onto the row, which is the shape the chat
  /// cubits decrypt from.
  static Map<String, dynamic> _flatten(Map<String, dynamic> row) {
    final sender = row['sender'] as Map<String, dynamic>?;
    return {
      ...row..remove('sender'),
      'sender_name': sender?['display_name'] ?? 'Unknown',
      'sender_public_key': sender?['public_key'],
      'sender_avatar_path': sender?['avatar_path'],
    };
  }

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

  /// Toggle the caller's [emoji] reaction on a message. [scope] is `channel`
  /// or `dm`. Returns `{reacted}`.
  ///
  /// Insert-then-fall-back-to-delete rather than read-then-write: the primary
  /// key is (message, user, emoji), so a duplicate is the database telling us
  /// the reaction was already there, with no window in between.
  Future<APIResponse> toggleReaction(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String scope,
    required int messageId,
    required String emoji,
  }) {
    final table = scope == 'dm' ? 'dm_message_reactions' : 'message_reactions';
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      try {
        await db.from(table).insert({
          'message_id': messageId,
          'user_id': userId,
          'emoji': emoji,
        });
        return {'reacted': true};
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
        await db
            .from(table)
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', userId)
            .eq('emoji', emoji);
        return {'reacted': false};
      }
    });
  }

  /// Aggregated reactions for [messageIds] — `{reactions: {id: [...]}}` with a
  /// count and whether the caller is in it.
  Future<APIResponse> listReactions(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String scope,
    required List<int> messageIds,
  }) {
    final table = scope == 'dm' ? 'dm_message_reactions' : 'message_reactions';
    return ServerDb.run(() async {
      if (messageIds.isEmpty) return {'reactions': <String, dynamic>{}};
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from(table)
          .select('message_id, user_id, emoji')
          .inFilter('message_id', messageIds);

      // Tallying here rather than in SQL keeps the round trip to one and the
      // rows are already scoped to messages the caller can see.
      final byMessage = <String, Map<String, ({int count, bool mine})>>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final id = '${row['message_id']}';
        final emoji = row['emoji'] as String;
        final existing =
            byMessage.putIfAbsent(id, () => {})[emoji] ??
            (count: 0, mine: false);
        byMessage[id]![emoji] = (
          count: existing.count + 1,
          mine: existing.mine || row['user_id'] == userId,
        );
      }
      return {
        'reactions': {
          for (final entry in byMessage.entries)
            entry.key: [
              for (final e in entry.value.entries)
                {'emoji': e.key, 'count': e.value.count, 'mine': e.value.mine},
            ],
        },
      };
    });
  }

  /// Store one E2E message envelope. Returns the server-attested id and time.
  Future<APIResponse> sendMessage(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required Map<String, dynamic> envelope,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db
          .from('messages')
          .insert({'channel_id': channelId, ...envelope})
          .select('id, created_at, channel_id, sender_id')
          .single();
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

  /// Page through a channel's envelopes. Pass [beforeId] for history
  /// (newest-first) or [afterId] for live catch-up (oldest-first).
  Future<APIResponse> listMessages(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final pageSize = limit ?? 50;
      var query = db
          .from('messages')
          .select(_messageColumns)
          .eq('channel_id', channelId);
      if (afterId != null) query = query.gt('id', afterId);
      if (beforeId != null) query = query.lt('id', beforeId);
      final rows = await query
          .order('id', ascending: afterId != null)
          .limit(pageSize);
      final messages = [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          _flatten(r),
      ];
      return {'messages': messages, 'has_more': messages.length == pageSize};
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

  /// Page through the DM conversation with [peerId].
  Future<APIResponse> listDms(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String peerId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final pageSize = limit ?? 50;
      var query = db
          .from('dm_messages')
          .select(_dmColumns)
          .or(
            'and(sender_id.eq.$userId,recipient_id.eq.$peerId),'
            'and(sender_id.eq.$peerId,recipient_id.eq.$userId)',
          );
      if (afterId != null) query = query.gt('id', afterId);
      if (beforeId != null) query = query.lt('id', beforeId);
      final rows = await query
          .order('id', ascending: afterId != null)
          .limit(pageSize);
      final messages = [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          _flatten(r),
      ];
      return {'messages': messages, 'has_more': messages.length == pageSize};
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
