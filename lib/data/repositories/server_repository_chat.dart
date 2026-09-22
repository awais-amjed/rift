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
/// The field `publishChatKey` answers with, and the field
/// `ChannelKeyring.ensureChatKeyPublished` reads to decide whether to ring the
/// key-sweep doorbell.
///
/// Named once and shared, because the two halves disagreeing is not a
/// hypothetical. The writer said `published`, the reader asked for
/// `newly_published`, and neither side looked wrong on its own — so the ring
/// that tells online members to seal a key for a new member never fired at
/// all, and every new member waited for somebody to open a channel by hand.
const String publishedChatKeyIsNew = 'newly_published';

mixin _ChatApiMixin {
  ServerDb get _db;

  /// Publish the caller's X25519 chat public key (idempotent).
  ///
  /// Answers [publishedChatKeyIsNew] beside `published`, and the difference is the
  /// whole point of the call. A member whose key has just appeared is a member
  /// nobody has sealed a channel key to, so
  /// [ChannelKeyring.ensureChatKeyPublished] rings the key-sweep doorbell on
  /// that answer and every online member wraps for them at once.
  ///
  /// It used to return `published` alone while the caller read
  /// `newly_published`, so the answer was always null, the ring never fired,
  /// and the comment saying "tell online members to wrap for us right away"
  /// described something that had never happened. Nothing looked broken —
  /// opening a text channel without a key rings the same doorbell, and that
  /// second ring covered for the first everywhere except a call, where there
  /// is no channel to open. A member whose first stop was voice waited until
  /// somebody else opened that channel by hand.
  Future<APIResponse> publishChatKey(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String chatPublicKey,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      // Read, then write only if it differs, rather than filtering the update
      // on the column: it is null for a member who has never published, and
      // PostgREST's `neq` never matches a null — so the one case that has to
      // answer "newly published" is exactly the one such a filter would skip.
      // Once per server per run, so the extra round trip costs nobody anything.
      final existing = await db
          .from('users')
          .select('chat_public_key')
          .eq('id', userId)
          .maybeSingle();
      if (existing?['chat_public_key'] == chatPublicKey) {
        return {'published': true, publishedChatKeyIsNew: false};
      }
      await db
          .from('users')
          .update({'chat_public_key': chatPublicKey})
          .eq('id', userId);
      return {'published': true, publishedChatKeyIsNew: true};
    });
  }

  /// Store one E2E message envelope. Returns the server-attested id and time.
  ///
  /// [mentions] and [mentionsAll] ride beside the envelope in the clear, and
  /// are the only part of a message that does. The server cannot open the
  /// envelope, so they are the only way it can tell a message that named
  /// somebody from one that did not — which is what a mentions-only channel
  /// turns on (`003_push.sql`, which argues the trade at length). They are
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
            // addressed to a bot that could never open it (`005_bots.sql`).
            'to_bot': ?toBot,
          })
          .select('id, created_at, channel_id, sender_id')
          .single();
    });
  }

  /// Press something on a bot's panel (`009_bot_voice.sql`).
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

  /// One page of conversations: an entry per peer with their identity material
  /// and the latest envelope, newest activity first.
  ///
  /// [before] is the newest message id of the last row already held — the
  /// cursor `dm_conversations` pages backwards on (`011_directory.sql`). Null asks
  /// for the top of the list. The reply is `{conversations, has_more}` as the
  /// RPC returns it; it used to be wrapped here because the RPC answered with a
  /// bare array and there was no second fact to carry.
  Future<APIResponse> listDmConversations(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    int? before,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return await db.rpc('dm_conversations', params: {'p_before': ?before});
    });
  }
}
