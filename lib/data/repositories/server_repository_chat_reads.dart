part of 'server_repository.dart';

/// Reading message envelopes off a self-hosted server: pages of history, and
/// one row at a time when a doorbell says it changed.
///
/// Every read here returns rows the caller may see under the row-level
/// security policies — the client does no filtering of its own beyond decrypting
/// and verifying what comes back.
mixin _ChatReadApiMixin {
  ServerDb get _db;

  /// The columns every message read needs, with the sender's profile, the
  /// message's reaction counts and its pin embedded.
  ///
  /// The sender FK has to be named explicitly: reactions added a second
  /// messages↔users relationship, and PostgREST refuses an ambiguous embed.
  ///
  /// Reactions ride along rather than being fetched after the page, so opening
  /// a channel is one round trip instead of two. They come as counts the
  /// server works out per message (`reaction_counts`, `[{emoji, count,
  /// mine}]`), checking once per message who may see them. Embedding every
  /// reaction row instead, as this did before, read 3.3 MB and took 220 ms for
  /// a page of announcements with 2,600 reactions each; the counts are 45 KB
  /// and 22 ms (Nov 25 2026). A server from before them is asked the old way
  /// ([_readRows]).
  static const _messageColumns =
      '$_messageFields, reactions:reaction_counts, message_pins(pinned_at)';

  static const _dmColumns =
      '$_dmFields, reactions:reaction_counts, dm_message_pins(pinned_at)';

  /// The same columns as a server from before `reaction_counts` is asked for
  /// them: every reaction row, folded into counts here.
  static const _oldMessageColumns =
      '$_messageFields, message_reactions(user_id, emoji), message_pins(pinned_at)';

  static const _oldDmColumns =
      '$_dmFields, dm_message_reactions(user_id, emoji), dm_message_pins(pinned_at)';

  static const _messageFields =
      'id, created_at, channel_id, sender_id, ciphertext, nonce, signature, '
      'key_version, edited_at, webhook_id, origin_name, is_system, to_bot, '
      'blocks, is_interaction, '
      'reply_to, ephemeral_for, poll, mentions_all, '
      'sender:users!messages_sender_id_fkey(display_name, public_key, avatar_path)';

  static const _dmFields =
      'id, created_at, sender_id, recipient_id, ciphertext, nonce, signature, '
      'key_version, edited_at, '
      'sender:users!dm_messages_sender_id_fkey(display_name, public_key, avatar_path)';

  /// Runs a read of message rows with the columns the server understands:
  /// [read] is handed the channel and DM column lists to select.
  ///
  /// A server from before `reaction_counts` (self-host 050) refuses the
  /// column with 42703, and is asked again with every reaction row embedded.
  /// That costs it one refused request a read until it is updated.
  static Future<APIResponse> _readRows(
    Future<dynamic> Function(({String messages, String dms}) columns) read,
  ) async {
    final response = await ServerDb.run(
      () => read((messages: _messageColumns, dms: _dmColumns)),
    );
    final old =
        response.errorCode == '42703' &&
        (response.error ?? '').contains('reaction_counts');
    if (!old) return response;
    return ServerDb.run(
      () => read((messages: _oldMessageColumns, dms: _oldDmColumns)),
    );
  }

  /// Lifts the embedded sender onto the row, takes the reaction counts (or
  /// tallies the embedded reaction rows of a server from before them), and
  /// lifts the pin (a one-to-one embed: an object or null) to `pinned_at` —
  /// the shape the chat cubits decrypt from.
  static Map<String, dynamic> _flatten(
    Map<String, dynamic> row, {
    required String? userId,
    required bool dm,
  }) {
    final reactionsKey = dm ? 'dm_message_reactions' : 'message_reactions';
    final pinsKey = dm ? 'dm_message_pins' : 'message_pins';
    final pin = row[pinsKey];
    final sender = row['sender'] as Map<String, dynamic>?;
    final embedded = row[reactionsKey] as List?;
    final reactions = embedded == null
        ? (row['reactions'] as List? ?? const [])
        : ReactionOps.aggregate(
            embedded.cast<Map<String, dynamic>>(),
            userId: userId,
          );
    // A webhook's message has no sender row to embed — `origin_name` is the
    // name, frozen on the message itself. Taking it here rather
    // than in each cubit keeps every reader on the same answer, and keeps the
    // 'Unknown' fallback for what it is actually for: a member whose row is
    // gone.
    final originName = row['origin_name'] as String?;
    return {
      ...row
        ..remove('sender')
        ..remove(reactionsKey)
        ..remove(pinsKey),
      'pinned_at': pin is Map ? pin['pinned_at'] : null,
      'sender_name': originName ?? sender?['display_name'] ?? 'Unknown',
      'sender_public_key': sender?['public_key'],
      'sender_avatar_path': sender?['avatar_path'],
      'reactions': reactions,
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
    return _readRows((columns) async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final pageSize = limit ?? ChatMessageOps.pageSize;
      // `channel_messages`, not `from('messages')`, and that is a performance
      // fix rather than a tidy-up. Messages from every channel share one table
      // and one sequence, so `order id.desc limit 51` can be answered by
      // walking the primary key — which means crossing everything every other
      // channel has said since this one last spoke. Opening a channel that had
      // gone quiet took 4.4 seconds against five million messages. The RPC
      // takes the page as ids first, off `idx_messages_channel`, and fetches
      // the rows by key: 1.5 ms, and 1.1 → 2,693 requests a second measured
      // end to end. See `app.channel_page_ids` for why it cannot be written
      // here.
      //
      // The ordering and the spare row are unchanged: the RPC returns newest
      // first, or oldest first when `p_after` is given, which is the order
      // this method has always produced.
      final rows = await db
          .rpc(
            'channel_messages',
            params: {
              'p_channel': channelId,
              'p_before': beforeId,
              'p_after': afterId,
              // One row past the page — see Paging.split.
              'p_limit': pageSize + 1,
            },
          )
          .select(columns.messages);
      final page = Paging.split(
        (rows as List).cast<Map<String, dynamic>>(),
        limit: pageSize,
      );
      return {
        'messages': [
          for (final r in page.rows) _flatten(r, userId: userId, dm: false),
        ],
        'has_more': page.hasMore,
      };
    });
  }

  /// A channel's open polls and live bot panels, newest first, wherever they
  /// sit in its history: what the bar above the message box holds. A server
  /// from before the read fails this like any other call, and the chat falls
  /// back on its loaded page.
  Future<APIResponse> listLiveMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
  }) {
    return _readRows((columns) async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .rpc('channel_live_messages', params: {'p_channel': channelId})
          .select(columns.messages);
      return {
        'messages': [
          for (final r in (rows as List).cast<Map<String, dynamic>>())
            _flatten(r, userId: userId, dm: false),
        ],
      };
    });
  }

  /// Servers from before `call_panels` (self-host 065), by address: asked
  /// once, then read channel by channel.
  final Set<String> _noCallPanels = {};

  /// What the bar of the voice call [callId] can hold, in one read: the
  /// call's players wherever each was posted, and the live panels of every
  /// text channel the caller reads. Each row has its own `channel_id`. A
  /// server from before it answers `PGRST202`, once.
  Future<APIResponse> listCallPanels(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String callId,
  }) async {
    if (_noCallPanels.contains(supabaseUrl)) {
      return APIResponse(
        success: false,
        error: 'This server has no call_panels',
        errorCode: 'PGRST202',
      );
    }
    final response = await _readRows((columns) async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .rpc('call_panels', params: {'p_call': callId})
          .select(columns.messages);
      return {
        'messages': [
          for (final r in (rows as List).cast<Map<String, dynamic>>())
            _flatten(r, userId: userId, dm: false),
        ],
      };
    });
    if (response.errorCode == 'PGRST202') _noCallPanels.add(supabaseUrl);
    return response;
  }

  /// Servers from before `channel_open` (self-host 066), by address: asked
  /// once, then read in five.
  final Set<String> _noChannelOpen = {};

  /// Everything [channelId] shows when it opens, in one request
  /// (`channel_open`): its newest page, the bar's rows, the caller's keys or
  /// why there are none, the bots holding a key to it and the bots a `/`
  /// there reaches, and how the polls among those rows stand. Answers
  /// `{page: {messages, has_more}, live: {messages}, key, key_error,
  /// listeners, bots: {users, has_more}, tallies}`, each part in the
  /// shape its own read answers. A server from before it answers `PGRST202`,
  /// once.
  Future<APIResponse> openChannel(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
    int? limit,
  }) async {
    if (_noChannelOpen.contains(supabaseUrl)) {
      return APIResponse(
        success: false,
        error: 'This server has no channel_open',
        errorCode: 'PGRST202',
      );
    }
    final response = await ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final pageSize = limit ?? ChatMessageOps.pageSize;
      final data = await db.rpc(
        'channel_open',
        params: {
          'p_channel': channelId,
          // One row past each page — see Paging.split.
          'p_limit': pageSize + 1,
          'p_bot_limit': MemberPage.pageSize + 1,
        },
      );
      final answer = data as Map<String, dynamic>;
      final page = Paging.split(
        (answer['messages'] as List).cast<Map<String, dynamic>>(),
        limit: pageSize,
      );
      final bots = Paging.split(
        _MemberApiMixin._members(answer['bots']),
        limit: MemberPage.pageSize,
      );
      return {
        'page': {
          'messages': [
            for (final r in page.rows) _flatten(r, userId: userId, dm: false),
          ],
          'has_more': page.hasMore,
        },
        'live': {
          'messages': [
            for (final r
                in (answer['live'] as List).cast<Map<String, dynamic>>())
              _flatten(r, userId: userId, dm: false),
          ],
        },
        'key': answer['key'],
        'key_error': answer['key_error'],
        'listeners': answer['listeners'],
        'bots': {'users': bots.rows, 'has_more': bots.hasMore},
        // Null from a server before self-host 083.
        'tallies': answer['tallies'],
      };
    });
    if (response.errorCode == 'PGRST202') _noChannelOpen.add(supabaseUrl);
    return response;
  }

  /// The live players of the bots in the voice call [callId], from whichever
  /// text channel each was posted in — one the caller cannot read included,
  /// since the player is the call's. A server from before the read fails this
  /// like any other call.
  Future<APIResponse> listCallLiveMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String callId,
  }) {
    return _readRows((columns) async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .rpc('call_live_messages', params: {'p_call': callId})
          .select(columns.messages);
      return {
        'messages': [
          for (final r in (rows as List).cast<Map<String, dynamic>>())
            _flatten(r, userId: userId, dm: false),
        ],
      };
    });
  }

  /// Page through the DM conversation with [peerId]. Pass [beforeId] for
  /// history (newest-first) or [afterId] for live catch-up (oldest-first).
  ///
  /// `dm_messages_page` reads the conversation off its own index. Asked as
  /// "sent by me to them, or by them to me", the server gathered every
  /// message the caller had ever sent or received to find it: a page of a
  /// 100,000-message conversation took 80 ms that way and 0.2 ms this way
  /// (Nov 26 2026). A server from before it (self-host 051) answers
  /// `PGRST202` and is asked the old way.
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
    return _readRows((columns) async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final pageSize = limit ?? ChatMessageOps.pageSize;
      List<dynamic> rows;
      try {
        rows = await db
            .rpc(
              'dm_messages_page',
              params: {
                'p_peer': peerId,
                'p_before': beforeId,
                'p_after': afterId,
                // One row past the page — see Paging.split.
                'p_limit': pageSize + 1,
              },
            )
            .select(columns.dms);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        var query = db
            .from('dm_messages')
            .select(columns.dms)
            .or(
              'and(sender_id.eq.$userId,recipient_id.eq.$peerId),'
              'and(sender_id.eq.$peerId,recipient_id.eq.$userId)',
            );
        if (afterId != null) query = query.gt('id', afterId);
        if (beforeId != null) query = query.lt('id', beforeId);
        rows = await query
            .order('id', ascending: afterId != null)
            .limit(pageSize + 1);
      }
      final page = Paging.split(
        rows.cast<Map<String, dynamic>>(),
        limit: pageSize,
      );
      return {
        'messages': [
          for (final r in page.rows) _flatten(r, userId: userId, dm: true),
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
    dm: false,
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
    dm: true,
    messageId: messageId,
  );

  /// Several channel messages by id, `{messages: […]}`: the quotes of a
  /// page's replies, read at once. An id with no row (deleted, or not this
  /// member's to see) is simply absent.
  Future<APIResponse> getMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
    required List<int> messageIds,
  }) => _getRows(
    supabaseUrl,
    anonKey: anonKey,
    userId: userId,
    bearerToken: bearerToken,
    dm: false,
    messageIds: messageIds,
    channelId: channelId,
  );

  /// Several server DMs by id, `{messages: […]}`, as [getMessages].
  Future<APIResponse> getDms(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required List<int> messageIds,
  }) => _getRows(
    supabaseUrl,
    anonKey: anonKey,
    userId: userId,
    bearerToken: bearerToken,
    dm: true,
    messageIds: messageIds,
  );

  /// The few columns a `message` or `dm` doorbell speaks about, as the
  /// database has them — `{message: null}` for a row that is not there or
  /// that this member may not see.
  ///
  /// A member can broadcast on the server's topic and a co-member on this
  /// one's own, so a ring's payload is anybody's to write (`app.can_use_topic`
  /// has to let clients send there, and Realtime checks that once per join,
  /// not per event). What the app says out loud is checked here first.
  Future<APIResponse> announcedRow(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required bool dm,
    required int messageId,
  }) => ServerDb.run(() async {
    final db = _db.client(supabaseUrl, anonKey, bearerToken);
    final row = await db
        .from(dm ? 'dm_messages' : 'messages')
        .select(
          dm
              ? 'id, sender_id, recipient_id'
              : 'id, channel_id, sender_id, mentions, mentions_all',
        )
        .eq('id', messageId)
        .maybeSingle();
    return {'message': row};
  });

  Future<APIResponse> _getRow(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required bool dm,
    required int messageId,
    String? channelId,
  }) {
    return _readRows((columns) async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      var query = db
          .from(dm ? 'dm_messages' : 'messages')
          .select(dm ? columns.dms : columns.messages)
          .eq('id', messageId);
      if (channelId != null) query = query.eq('channel_id', channelId);
      final row = await query.maybeSingle();
      return {
        'message': row == null ? null : _flatten(row, userId: userId, dm: dm),
      };
    });
  }

  Future<APIResponse> _getRows(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required bool dm,
    required List<int> messageIds,
    String? channelId,
  }) {
    return _readRows((columns) async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      var query = db
          .from(dm ? 'dm_messages' : 'messages')
          .select(dm ? columns.dms : columns.messages)
          .inFilter('id', messageIds);
      if (channelId != null) query = query.eq('channel_id', channelId);
      final rows = await query;
      return {
        'messages': [for (final r in rows) _flatten(r, userId: userId, dm: dm)],
      };
    });
  }
}
