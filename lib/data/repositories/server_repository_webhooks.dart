part of 'server_repository.dart';

/// Webhook management on a self-hosted server (migration 013, BOTS.md §7).
///
/// Reads and deletes are direct table calls under `webhooks_select` /
/// `webhooks_delete`, both of which require `app.can_manage_channels()`.
/// Creating one is not: minting the secret is the whole operation, and a secret
/// the caller chose is not a secret — so it goes through `create_webhook`,
/// which is also where the per-channel ceiling lives.
///
/// Nothing here can read a secret back. `secret_hash` has no column grant at
/// all, so it never leaves the database even for the admin who made it.
mixin _WebhookApiMixin {
  ServerDb get _db;

  /// Every webhook posting into [channelId], newest first.
  Future<APIResponse> listWebhooks(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('webhooks')
          .select('id, channel_id, name, created_at, last_used_at')
          .eq('channel_id', channelId)
          .order('created_at', ascending: false);
      return {'webhooks': (rows as List).cast<Map<String, dynamic>>()};
    });
  }

  /// Mint one. Returns `{reason, id, secret}` — and the secret is the only copy
  /// there will ever be, so a caller that drops it has lost it.
  Future<APIResponse> createWebhook(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required String name,
  }) {
    return ServerDb.run(() async {
      final result = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'create_webhook',
            params: {'p_channel_id': channelId, 'p_name': name},
          );
      return (result as Map).cast<String, dynamic>();
    });
  }

  /// Revoke one. Its messages stay where they are — they render from the name
  /// frozen on each row, not from this table.
  Future<APIResponse> deleteWebhook(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String webhookId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db.from('webhooks').delete().eq('id', webhookId);
      return {'deleted': true};
    });
  }

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

  /// Hand a bot the key to one channel, or take it back.
  ///
  /// RPCs, and they have to be. A grant decides which key version the bot
  /// starts at — one past the current, which is the whole of forward-only —
  /// and a revoke drops the sealed rows so the sweep sees a bot with no grant
  /// and rotates. Neither is a fact a client could work out, and
  /// `bot_channel_keys` has no write grant at all so neither can be faked
  /// (migrations 017, 028).
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
}
