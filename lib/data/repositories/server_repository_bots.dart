part of 'server_repository.dart';

/// What a bot may read, and what it may hear (BOTS.md §6, `005_bots.sql` and `009_bot_voice.sql`,
/// 030 and 031).
///
/// Split out of the webhook file next door, which is the opposite thing wearing
/// the same shape: a webhook *writes* into a channel without being a member,
/// and everything here decides what a bot may *receive*. The two grew together
/// because they arrived together, and they have nothing else in common.
///
/// Two kinds of access live here and they are not the same promise:
///
/// - **A channel key** is arithmetic. Revoking rotates forward; it cannot
///   unread what has been read.
/// - **Hearing a call** is a permission. Voice is not end-to-end encrypted
///   (ARCHITECTURE.md §5), so subscription is a flag on a LiveKit token and
///   revoking really does stop the audio.
///
/// Saying that difference out loud is the point of keeping them adjacent.

mixin _BotApiMixin {
  ServerDb get _db;

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// Which bots hold a key to [channelId] — the channel's standing notice.
  ///
  /// Every member may read this, and that is rule 4 of BOTS.md §6 rather than
  /// an oversight. The admin grants; **every member's future messages pay for
  /// it**, so a warning that lived only in the admin's dialog would reach the
  /// wrong audience entirely.
  Future<APIResponse> listChannelListeners(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('channel_bot_listeners')
          .select('bot_id, username, display_name, granted_by_name, granted_at')
          .eq('channel_id', channelId)
          .order('display_name');
      return {'listeners': (rows as List).cast<Map<String, dynamic>>()};
    });
  }

  /// Hand a bot the key to every public channel, or take it all back.
  ///
  /// One RPC rather than a loop of per-channel calls, and not for speed: the
  /// grant is *standing*, so a channel created next week is covered too. A
  /// client looping over today's channels would produce a bot that silently
  /// stops working in tomorrow's (`009_bot_voice.sql`).
  Future<APIResponse> setBotServerKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String botId,
    required bool granted,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        granted ? 'grant_bot_server_key' : 'revoke_bot_server_key',
        params: {'p_bot': botId},
      );
    });
  }

  /// Every channel this bot can read, and whether the grant is server-wide.
  ///
  /// The answer to "what does this thing see?", in one place. Before this it
  /// was discoverable a channel at a time, which is not an answer somebody can
  /// act on (BOTS.md §6).
  Future<APIResponse> listBotChannels(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String botId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('bot_channel_keys')
          .select('channel_id')
          .eq('bot_id', botId);
      final serverWide = await db
          .from('bot_server_grants')
          .select('bot_id')
          .eq('bot_id', botId);
      return {
        'channel_ids': [
          for (final r in (rows as List).cast<Map<String, dynamic>>())
            r['channel_id'] as String,
        ],
        'server_wide': (serverWide as List).isNotEmpty,
      };
    });
  }

  /// Hand a bot the key to one channel, or take it back.
  ///
  /// RPCs, and they have to be. A grant decides which key version the bot
  /// starts at — one past the current, which is the whole of forward-only —
  /// and a revoke drops the sealed rows so the sweep sees a bot with no grant
  /// and rotates. Neither is a fact a client could work out, and
  /// `bot_channel_keys` has no write grant at all so neither can be faked
  /// (`005_bots.sql` and `009_bot_voice.sql`).
  Future<APIResponse> setBotChannelKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required String botId,
    required bool granted,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        granted ? 'grant_bot_channel_key' : 'revoke_bot_channel_key',
        params: {'p_bot': botId, 'p_channel': channelId},
      );
    });
  }

  /// Which bots can hear [channelId] — the voice channel's standing notice.
  ///
  /// The same audience rule as [listChannelListeners]: an admin decides, and
  /// everybody who ever speaks in that room pays for it, so this is readable by
  /// every member who can see the channel rather than by the person who
  /// granted it.
  /// Bots summoned into voice channels, with the name to draw (`010_bot_permissions.sql`).
  ///
  /// The sibling of [listVoiceListeners] and the same shape, but not the same
  /// meaning: a listener is a warning and a summon is furniture. It exists so a
  /// summon whose bot never turned up is visible — "Send away" lives on the
  /// participant menu, which needs the bot to be in the call, so without this
  /// one that never arrived could be neither seen nor cleared.
  Future<APIResponse> listVoiceSummons(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    String? channelId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final query = db
          .from('voice_summons')
          .select('channel_id, bot_id, bot_name');
      final rows = channelId == null
          ? await query.order('bot_name')
          : await query.eq('channel_id', channelId).order('bot_name');
      return {'summons': rows};
    });
  }

  Future<APIResponse> listVoiceListeners(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    String? channelId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      // No channel filter means every voice channel at once, which is what the
      // sidebar needs: one round trip for the whole list rather than one per
      // channel drawn.
      final query = db
          .from('voice_listeners')
          .select('channel_id, bot_id, bot_name');
      final rows = channelId == null
          ? await query.order('bot_name')
          : await query.eq('channel_id', channelId).order('bot_name');
      return {'listeners': (rows as List).cast<Map<String, dynamic>>()};
    });
  }

  /// Seal one bot the key it speaks with in one voice channel.
  ///
  /// A plain insert, not an RPC: the value is opaque to the server and every
  /// rule about who may write one is in 032's policy — a member of the room,
  /// never a bot, and `is_channel_key` only where a listening grant exists.
  /// A conflict means another member's client got there first, which is the
  /// same non-event it is when healing a member.
  Future<APIResponse> postBotVoiceKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required String botId,
    required int keyVersion,
    required bool isChannelKey,
    required Map<String, dynamic> wrapped,
    required String wrappedBy,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db.from('bot_voice_keys').upsert({
        'channel_id': channelId,
        'bot_id': botId,
        'key_version': keyVersion,
        'is_channel_key': isChannelKey,
        'wrapped_by': wrappedBy,
        ...wrapped,
      }, ignoreDuplicates: true);
      return {'sealed': true};
    });
  }

  /// Let a bot hear a voice channel, or stop it hearing one.
  ///
  /// An edge function rather than the RPC directly, for the same reason
  /// [moderateUser] is one: the row is half the job. A bot already in the call
  /// holds a token whose grant said `canSubscribe`, and a token is good for its
  /// hour no matter what the table says — so revoking without the live push
  /// would leave it listening for up to an hour behind a light drawn as off.
  /// The function calls the RPC with the caller's JWT, so the permission rules
  /// stay in the database (`009_bot_voice.sql`).
  Future<APIResponse> setBotVoiceListen(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required String botId,
    required bool listen,
  }) {
    return _post(supabaseUrl, 'set_bot_voice_listen', {
      'bot_id': botId,
      'channel_id': channelId,
      'listen': listen,
    }, bearerToken: bearerToken);
  }
}
