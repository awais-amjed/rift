part of 'server_repository.dart';

/// Reading message envelopes off a self-hosted server: pages of history, and
/// one row at a time when a doorbell says it changed.
///
/// Every read here returns rows the caller may see under the policies in
/// migration 002 — the client does no filtering of its own beyond decrypting
/// and verifying what comes back.
mixin _ChatReadApiMixin {
  ServerDb get _db;

  /// The columns every message read needs, with the sender's profile and the
  /// message's reactions embedded.
  ///
  /// The sender FK has to be named explicitly: reactions added a second
  /// messages↔users relationship, and PostgREST refuses an ambiguous embed.
  ///
  /// Reactions ride along rather than being fetched after the page, so opening
  /// a channel is one round trip instead of two and the cost stops growing with
  /// how far the reader has scrolled. RLS applies to the embed as it does to a
  /// standalone read, so this widens nothing.
  static const _messageColumns =
      'id, created_at, channel_id, sender_id, ciphertext, nonce, signature, '
      'key_version, edited_at, webhook_id, origin_name, is_system, to_bot, '
      'blocks, is_interaction, '
      'reply_to, ephemeral_for, '
      'sender:users!messages_sender_id_fkey(display_name, public_key, avatar_path), '
      'message_reactions(user_id, emoji)';

  static const _dmColumns =
      'id, created_at, sender_id, recipient_id, ciphertext, nonce, signature, '
      'key_version, edited_at, '
      'sender:users!dm_messages_sender_id_fkey(display_name, public_key, avatar_path), '
      'dm_message_reactions(user_id, emoji)';

  /// Lifts the embedded sender onto the row and tallies the embedded reaction
  /// rows into counts, which is the shape the chat cubits decrypt from.
  static Map<String, dynamic> _flatten(
    Map<String, dynamic> row, {
    required String? userId,
    required String reactionsKey,
  }) {
    final sender = row['sender'] as Map<String, dynamic>?;
    final reactions = (row[reactionsKey] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    // A webhook's message has no sender row to embed — `origin_name` is the
    // name, frozen on the message itself (migration 013). Taking it here rather
    // than in each cubit keeps every reader on the same answer, and keeps the
    // 'Unknown' fallback for what it is actually for: a member whose row is
    // gone.
    final originName = row['origin_name'] as String?;
    return {
      ...row
        ..remove('sender')
        ..remove(reactionsKey),
      'sender_name': originName ?? sender?['display_name'] ?? 'Unknown',
      'sender_public_key': sender?['public_key'],
      'sender_avatar_path': sender?['avatar_path'],
      'reactions': ReactionOps.aggregate(reactions, userId: userId),
    };
  }

  /// Page through a channel's envelopes. Pass [beforeId] for history
  /// (newest-first) or [afterId] for live catch-up (oldest-first).
  Future<APIResponse> listMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final pageSize = limit ?? ChatMessageOps.pageSize;
      var query = db
          .from('messages')
          .select(_messageColumns)
          .eq('channel_id', channelId);
      if (afterId != null) query = query.gt('id', afterId);
      if (beforeId != null) query = query.lt('id', beforeId);
      // One row past the page — see Paging.split.
      final rows = await query
          .order('id', ascending: afterId != null)
          .limit(pageSize + 1);
      final page = Paging.split(
        (rows as List).cast<Map<String, dynamic>>(),
        limit: pageSize,
      );
      return {
        'messages': [
          for (final r in page.rows)
            _flatten(r, userId: userId, reactionsKey: 'message_reactions'),
        ],
        'has_more': page.hasMore,
      };
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
      final pageSize = limit ?? ChatMessageOps.pageSize;
      var query = db
          .from('dm_messages')
          .select(_dmColumns)
          .or(
            'and(sender_id.eq.$userId,recipient_id.eq.$peerId),'
            'and(sender_id.eq.$peerId,recipient_id.eq.$userId)',
          );
      if (afterId != null) query = query.gt('id', afterId);
      if (beforeId != null) query = query.lt('id', beforeId);
      // One row past the page — see Paging.split.
      final rows = await query
          .order('id', ascending: afterId != null)
          .limit(pageSize + 1);
      final page = Paging.split(
        (rows as List).cast<Map<String, dynamic>>(),
        limit: pageSize,
      );
      return {
        'messages': [
          for (final r in page.rows)
            _flatten(r, userId: userId, reactionsKey: 'dm_message_reactions'),
        ],
        'has_more': page.hasMore,
      };
    });
  }

  /// One channel message by id, or `{message: null}` when it is gone.
  ///
  /// The single-row half of the change doorbell: a ring names a message, and
  /// this is how the receiver finds out what actually happened to it. An edit
  /// answers with the new envelope; a delete answers with nothing, because the
  /// row is hard-deleted. Asking the database rather than trusting the ping is
  /// what keeps a forged broadcast down to a wasted request.
  Future<APIResponse> getMessage(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
    required int messageId,
  }) => _getRow(
    supabaseUrl,
    anonKey: anonKey,
    userId: userId,
    bearerToken: bearerToken,
    table: 'messages',
    columns: _messageColumns,
    reactionsKey: 'message_reactions',
    messageId: messageId,
    channelId: channelId,
  );

  /// One server DM by id, or `{message: null}` when it is gone.
  Future<APIResponse> getDm(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required int messageId,
  }) => _getRow(
    supabaseUrl,
    anonKey: anonKey,
    userId: userId,
    bearerToken: bearerToken,
    table: 'dm_messages',
    columns: _dmColumns,
    reactionsKey: 'dm_message_reactions',
    messageId: messageId,
  );

  Future<APIResponse> _getRow(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String table,
    required String columns,
    required String reactionsKey,
    required int messageId,
    String? channelId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      var query = db.from(table).select(columns).eq('id', messageId);
      if (channelId != null) query = query.eq('channel_id', channelId);
      final row = await query.maybeSingle();
      return {
        'message': row == null
            ? null
            : _flatten(row, userId: userId, reactionsKey: reactionsKey),
      };
    });
  }
}
