import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart' hide ErrorCode;

import '../../logic/services/chat_message_ops.dart';
import '../../logic/services/reaction_ops.dart';
import '../classes/api_response.dart';
import '../classes/server_limits.dart';
import '../enums/error_code.dart';
import 'server_db.dart';

part 'server_repository_channels.dart';
part 'server_repository_chat.dart';
part 'server_repository_chat_reads.dart';
part 'server_repository_push.dart';
part 'server_repository_reactions.dart';
part 'server_repository_webhooks.dart';

/// All I/O against a self-hosted server.
///
/// Two transports, and which one a call uses is not arbitrary. Almost
/// everything is a **direct PostgREST call** under the policies in migration
/// 002 — reading messages, sending one, editing your own, member lists,
/// channels, invites, read cursors. What remains an **edge function** is only
/// what genuinely can't be a table call:
///
///   * it needs a secret the client must never hold — `get_channel_token`
///     (LiveKit API secret), `create_server`, `login` (GoTrue admin grant);
///   * it runs before the caller is a member, or before they have a key at all
///     — `resolve_invite`, `register`, `is_username_available`;
///   * key distribution (`get_channel_key`, `post_channel_keys`,
///     `sweep_channel_keys`), which enforces the channel-key version race and
///     is deliberately left alone until it can be moved with care.
///
/// Everything else was an endpoint that existed only because clients weren't
/// trusted with the database — which was never a decision, just a consequence
/// of tables without policies.
class ServerRepository
    with
        _ChannelApiMixin,
        _ChatApiMixin,
        _ChatReadApiMixin,
        _PushApiMixin,
        _ReactionApiMixin,
        _WebhookApiMixin {
  @override
  final ServerDb _db = ServerDb();

  /// A stable per-run device id, mixed into LiveKit participant identities so
  /// the same user can be connected from multiple devices without the later
  /// connection kicking the earlier one. It only has to be consistent within a
  /// single app run — long enough for a voice session and its screen-share to
  /// share it — so an in-memory value (regenerated each launch) is sufficient;
  /// per-user state persists under the user id, not the identity.
  static final String _deviceId = _generateDeviceId();

  static String _generateDeviceId() {
    final rng = Random.secure();
    return List.generate(
      8,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  // ──────────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────────

  @override
  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    try {
      final uri = Uri.parse('$supabaseUrl/functions/v1/$functionName');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      return _fromSupabaseCF(result);
    } on TimeoutException {
      return APIResponse.error(
        "This server isn't responding — it may be offline. Try again later.",
        errorCode: ErrorCode.serverTimeout,
      );
    } catch (e) {
      // Distinguish "can't reach the server" from other failures so the UI can
      // show a friendly offline message instead of a raw exception.
      final msg = e.toString().toLowerCase();
      final isConnectionError =
          e is http.ClientException ||
          msg.contains('socketexception') ||
          msg.contains('failed host lookup') ||
          msg.contains('connection refused') ||
          msg.contains('connection closed') ||
          msg.contains('network is unreachable');
      if (isConnectionError) {
        return APIResponse.error(
          "Can't reach this server. It may be offline, or check your connection.",
          errorCode: ErrorCode.serverUnreachable,
        );
      }
      return APIResponse.error(e);
    }
  }

  APIResponse _fromSupabaseCF(Map<String, dynamic> data) {
    if (data['success'] == true) {
      return APIResponse.success(data['data']);
    }
    return APIResponse(
      success: false,
      error: data['error'] as String? ?? 'Unknown error',
      errorCode: data['code'] as String?,
    );
  }

  // ──────────────────────────────────────────────────────────
  // Server
  // ──────────────────────────────────────────────────────────

  /// Create a new server. Returns server_id, name, supabase_url,
  /// supabase_key, and invite_code for the admin to register with.
  Future<APIResponse> createServer(
    String supabaseUrl, {
    required String serviceKey,
    required String name,
    String? iconUrl,
    required String livekitUrl,
    required String livekitApiKey,
    required String livekitSecretKey,
  }) {
    return _post(supabaseUrl, 'create_server', {
      'service_key': serviceKey,
      'name': name,
      'icon_url': iconUrl,
      'livekit_url': livekitUrl,
      'livekit_api_key': livekitApiKey,
      'livekit_secret_key': livekitSecretKey,
    });
  }

  /// Server metadata, its channels, and the caller's own profile row.
  ///
  /// Three selects rather than an endpoint that assembled them. `supabase_key`
  /// is echoed back from what the caller already had: it used to come from the
  /// server's environment, but by the time anyone can ask this question they
  /// are holding the key that let them ask.
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      // Our own row first, because it is the only one a banned member can
      // still read (`users_select_self`) and it decides whether the rest is
      // worth asking for.
      final user = await db
          .from('users')
          .select(
            'id, username, display_name, avatar_path, is_muted, is_deafened, '
            'is_banned, is_server_admin, is_channel_manager, can_create_tokens',
          )
          .eq('id', _uidOf(bearerToken) ?? '')
          .maybeSingle();

      // A ban makes `app.server_id()` null, so every other policy on the
      // server stops matching — including the one over `servers` itself. Read
      // in the old order that came back as "Server not found", the refresh
      // failed, and the client was left with stale channels and no idea why
      // nothing worked. It isn't missing; we are barred from it, which is the
      // one answer worth returning, and it is in the row we can still read.
      if (user != null && user['is_banned'] == true) {
        return {
          'supabase_key': anonKey,
          'channels': const <Map<String, dynamic>>[],
          'user': _userRow(user),
        };
      }

      final server = await db
          .from('servers')
          .select('id, name, icon_url, livekit_url, $_limitColumns')
          .limit(1)
          .maybeSingle();
      if (server == null) {
        throw const PostgrestException(message: 'Server not found');
      }
      final channels = await db
          .from('channels')
          .select('id, name, channel_type, retention_days, history_cap, is_private')
          .order('name');

      // Best-effort: a server that predates 021 has no such function, and the
      // three cached booleans on the user row still answer the three questions
      // a client could ask before this existed.
      int bits = 0;
      try {
        bits = (await db.rpc('my_permissions') as num?)?.toInt() ?? 0;
      } catch (_) {}

      return {
        'server_id': server['id'],
        'name': server['name'],
        'icon_url': server['icon_url'],
        'livekit_url': server['livekit_url'],
        'supabase_key': anonKey,
        'channels': channels,
        'user': user == null ? null : _withPermissionBits(_userRow(user), bits),
        // Flat, so ServerLimits.fromJson reads this map and the
        // update_server response with the same code.
        ...ServerLimits.fromJson(server).toJson(),
      };
    });
  }

  /// The operator-limit columns added in migration 007, in the order
  /// [ServerLimits] reads them.
  static const _limitColumns =
      'max_attachment_bytes, message_retention_days, message_history_cap';

  /// Update server settings (admin only).
  ///
  /// One of the few things still on an edge function, and for the usual
  /// reason: it writes the LiveKit API key and secret. Those live in
  /// `server_secrets`, which has no client-reachable path at all, so the write
  /// has to happen somewhere holding the service role. Name, icon and the
  /// operator limits ride along rather than splitting one dialog across two
  /// transports — and the limits have a second reason to be here: saving the
  /// attachment cap also has to move the storage bucket's `file_size_limit`,
  /// which no client-reachable grant can do.
  Future<APIResponse> updateServer(
    String supabaseUrl, {
    String? bearerToken,
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
    ServerLimits? limits,
  }) {
    return _post(supabaseUrl, 'update_server', {
      'name': ?name,
      'icon_url': ?iconUrl,
      'livekit_url': ?livekitUrl,
      'livekit_api_key': ?livekitApiKey,
      'livekit_secret_key': ?livekitSecretKey,
      ...?limits?.toJson(),
    }, bearerToken: bearerToken);
  }

  /// The `sub` claim of a JWT, without verifying it — the client is reading its
  /// own token to know which row is "mine", and the server re-checks anyway.
  static String? _uidOf(String? jwt) {
    if (jwt == null) return null;
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      return (jsonDecode(payload) as Map<String, dynamic>)['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Flattens a `users` row into the shape the client models expect, with
  /// permissions nested.
  /// Folds the caller's own permission bits into the nested `permissions` map
  /// `ServerUser` reads, so the three cached booleans and the twenty-two bits
  /// arrive as one answer rather than two the client has to reconcile.
  static Map<String, dynamic> _withPermissionBits(
    Map<String, dynamic> row,
    int bits,
  ) => {
    ...row,
    'permissions': {
      ...(row['permissions'] as Map<String, dynamic>),
      'permission_bits': bits,
    },
  };

  static Map<String, dynamic> _userRow(Map<String, dynamic> u) => {
    'id': u['id'],
    'username': u['username'],
    'display_name': u['display_name'],
    'avatar_path': u['avatar_path'],
    'chat_public_key': u['chat_public_key'],
    'is_muted': u['is_muted'],
    'is_deafened': u['is_deafened'],
    'is_banned': u['is_banned'],
    'is_bot': u['is_bot'],
    'manifest': u['manifest'],
    'permissions': {
      'is_server_admin': u['is_server_admin'],
      'is_channel_manager': u['is_channel_manager'],
      'can_create_tokens': u['can_create_tokens'],
    },
  };

  // ──────────────────────────────────────────────────────────
  // Registration & Auth
  // ──────────────────────────────────────────────────────────

  /// Sign in with a SIWS message + signature. Proxied to GoTrue's web3 grant
  /// server-side (so no anon key is needed client-side). Returns the GoTrue
  /// session (access_token + refresh_token).
  Future<APIResponse> login(
    String supabaseUrl, {
    required String message,
    required String signature,
  }) {
    return _post(supabaseUrl, 'login', {
      'message': message,
      'signature': signature,
    });
  }

  /// Resolve an invite code to its server (id + name) without consuming it.
  /// Needed before login/register so the per-(host, serverId) SIWS identity can
  /// be derived when several servers share one Supabase project.
  Future<({bool success, String? serverId, String? serverName, String? error})>
  resolveInvite(String supabaseUrl, String inviteCode) async {
    final response = await _post(supabaseUrl, 'resolve_invite', {
      'invite_code': inviteCode,
    });
    if (!response.success || response.data is! Map) {
      return (
        success: false,
        serverId: null,
        serverName: null,
        error: response.error,
      );
    }
    final data = response.data as Map<String, dynamic>;
    return (
      success: true,
      serverId: data['server_id'] as String?,
      serverName: data['server_name'] as String?,
      error: null,
    );
  }

  /// Register a server profile bound to the caller's SIWS identity.
  /// [bearerToken] is the GoTrue access token obtained from [login]. Returns
  /// full server context (no token — the client already holds the JWT).
  Future<APIResponse> register(
    String supabaseUrl, {
    required String bearerToken,
    required String inviteCode,
    required String publicKey,
    required String stableId,
    required String username,
    required String displayName,
  }) {
    return _post(supabaseUrl, 'register', {
      'invite_code': inviteCode,
      'public_key': publicKey,
      'stable_id': stableId,
      'username': username,
      'display_name': displayName,
    }, bearerToken: bearerToken);
  }

  /// Check whether a username is available on the given server.
  Future<APIResponse> isUsernameAvailable(String supabaseUrl, String username) {
    return _post(supabaseUrl, 'is_username_available', {'username': username});
  }

  /// Create a plain invite code. Invites carry no permissions — members
  /// join with baseline access and admins promote them afterwards via
  /// [setUserPermissions].
  /// [maxUses] null = unlimited, 1 = single-use (default).
  /// [expiresInSeconds] null = never expires.
  /// The code is generated by the column default, and the policy refuses any
  /// permission the caller doesn't hold themselves.
  Future<APIResponse> createInvite(
    String supabaseUrl, {
    required String anonKey,
    required String serverId,
    required String userId,
    String? bearerToken,
    int? maxUses = 1,
    int? expiresInSeconds,
    bool isBot = false,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final row = await db
          .from('invites')
          .insert({
            'server_id': serverId,
            'created_by': userId,
            'max_uses': maxUses,
            // Decided when the link is minted and never afterwards — there is
            // no UPDATE grant on invites, so one link cannot quietly become the
            // other kind (migration 014).
            'is_bot': isBot,
            if (expiresInSeconds != null)
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(Duration(seconds: expiresInSeconds))
                  .toIso8601String(),
          })
          .select('code')
          .single();
      return {'invite_code': row['code']};
    });
  }

  /// Update the caller's own display name and/or avatar path.
  /// [clearAvatar] sends an explicit null, which removes the picture.
  ///
  /// There is no target parameter and there cannot be one: the column grant
  /// covers only these fields, and the policy only ever matches your own row.
  Future<APIResponse> updateProfile(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    String? displayName,
    String? avatarPath,
    bool clearAvatar = false,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final row = await db
          .from('users')
          .update({
            'display_name': ?displayName,
            if (clearAvatar)
              'avatar_path': null
            else
              'avatar_path': ?avatarPath,
          })
          .eq('id', userId)
          .select('id, username, display_name, avatar_path')
          .single();
      return row;
    });
  }

  /// Every member of the server, with permissions and moderation state.
  /// Members can see each other; changing any of it goes through the RPCs.
  Future<APIResponse> listUsers(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('users')
          .select(
            'id, username, display_name, avatar_path, chat_public_key, '
            'is_muted, is_deafened, is_banned, is_bot, manifest, '
            'is_server_admin, is_channel_manager, can_create_tokens',
          )
          .order('username');
      return {
        'users': [
          for (final u in (rows as List).cast<Map<String, dynamic>>())
            _userRow(u),
        ],
      };
    });
  }

  /// Set a user's permission flags (server admin only; not your own).
  Future<APIResponse> setUserPermissions(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'set_user_permissions',
        params: {
          'p_target': userId,
          'p_is_server_admin': isServerAdmin,
          'p_is_channel_manager': isChannelManager,
          'p_can_create_tokens': canCreateTokens,
        },
      );
    });
  }

  // ──────────────────────────────────────────────────────────
  // Channels — voice tokens. The CRUD is in the channels part.
  // ──────────────────────────────────────────────────────────

  /// Get a LiveKit JWT for joining a channel.
  Future<APIResponse> getChannelToken(
    String supabaseUrl,
    String channelId, {
    bool screenShare = false,
    String? bearerToken,
  }) {
    return _post(supabaseUrl, 'get_channel_token', {
      'channel_id': channelId,
      'screen_share': screenShare,
      'device_id': _deviceId,
    }, bearerToken: bearerToken);
  }

  /// Apply the server's retention settings and remove the attachment blobs
  /// left behind (migration 007).
  ///
  /// An edge function rather than a table call, and not for the usual reason:
  /// this one needs the *Storage API*. `storage.protect_delete()` refuses a
  /// direct DELETE on `storage.objects`, so no database role can free a blob —
  /// only something holding the service key can finish the job.
  Future<APIResponse> sweepAttachments(
    String supabaseUrl, {
    String? bearerToken,
  }) => _post(
    supabaseUrl,
    'sweep_attachments',
    const {},
    bearerToken: bearerToken,
  );

  /// Pull a member from the voice channel they're in into [channelId]
  /// (channel manager or admin).
  ///
  /// Nothing is written down — a move only exists as a live connection — so
  /// there is no table call to make. The function holds the LiveKit API secret
  /// and uses it to send the target's own connections a "join this channel"
  /// packet, which their client then does the ordinary way.
  Future<APIResponse> moveUser(
    String supabaseUrl, {
    String? bearerToken,
    required String userId,
    required String channelId,
  }) {
    return _post(supabaseUrl, 'move_user', {
      'target_user_id': userId,
      'channel_id': channelId,
    }, bearerToken: bearerToken);
  }

  /// Disconnect a member from the voice channel they're in (channel manager
  /// or admin).
  ///
  /// The transient half of moderation: nothing is written down and they may
  /// rejoin immediately. Like [moveUser] it needs the LiveKit API secret, and
  /// like it there is no table call to make — the difference is that this ends
  /// every connection they hold here, screen share included.
  Future<APIResponse> kickUser(
    String supabaseUrl, {
    String? bearerToken,
    required String userId,
  }) {
    return _post(supabaseUrl, 'kick_user', {
      'target_user_id': userId,
    }, bearerToken: bearerToken);
  }

  /// Who is in which voice channel right now, as LiveKit sees it:
  /// `{roster: {userId: channelId}}`.
  ///
  /// The snapshot a client starts from before it can rely on hearing about
  /// changes — see [VoiceBroadcast].
  Future<APIResponse> voiceRoster(String supabaseUrl, {String? bearerToken}) {
    return _post(
      supabaseUrl,
      'voice_roster',
      const {},
      bearerToken: bearerToken,
    );
  }

  /// Unread counts for every channel and conversation on this server, in one
  /// call: `{channels: {id: n}, dms: {peerId: n}}`.
  Future<APIResponse> unreadCounts(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc('unread_counts');
    });
  }

  /// Move a read cursor forward. Omit [lastReadId] to mean "everything there
  /// is right now". Never moves backwards, so two devices can't un-read each
  /// other's progress.
  Future<APIResponse> markRead(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String scope,
    required String scopeId,
    int lastReadId = 0,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'mark_read',
        params: {
          'p_scope': scope,
          'p_scope_id': scopeId,
          'p_last_read_id': lastReadId,
        },
      );
    });
  }
}
