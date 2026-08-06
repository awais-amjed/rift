import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../classes/api_response.dart';
import '../enums/error_code.dart';

part 'server_repository_chat.dart';

/// Repository for all Supabase Edge Function API calls.
class ServerRepository with _ChatApiMixin {
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

  /// Get full server details (name, icon, channels, current user).
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    String? bearerToken,
  }) {
    return _post(
      supabaseUrl,
      'get_server_details',
      {},
      bearerToken: bearerToken,
    );
  }

  /// Update server details (admin only).
  Future<APIResponse> updateServer(
    String supabaseUrl, {
    String? bearerToken,
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
  }) {
    return _post(supabaseUrl, 'update_server', {
      'name': ?name,
      'icon_url': ?iconUrl,
      'livekit_url': ?livekitUrl,
      'livekit_api_key': ?livekitApiKey,
      'livekit_secret_key': ?livekitSecretKey,
    }, bearerToken: bearerToken);
  }

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
  Future<APIResponse> createInvite(
    String supabaseUrl, {
    String? bearerToken,
    int? maxUses = 1,
    int? expiresInSeconds,
  }) {
    return _post(supabaseUrl, 'create_invite', {
      'max_uses': maxUses,
      'expires_in_seconds': ?expiresInSeconds,
    }, bearerToken: bearerToken);
  }

  /// List all members of the server with permissions and moderation state.
  /// Update the caller's own display name and/or avatar path.
  /// [clearAvatar] sends an explicit null, which removes the picture.
  Future<APIResponse> updateProfile(
    String supabaseUrl, {
    String? bearerToken,
    String? displayName,
    String? avatarPath,
    bool clearAvatar = false,
  }) {
    return _post(supabaseUrl, 'update_profile', {
      'display_name': ?displayName,
      if (clearAvatar) 'avatar_path': null else 'avatar_path': ?avatarPath,
    }, bearerToken: bearerToken);
  }

  Future<APIResponse> listUsers(String supabaseUrl, {String? bearerToken}) {
    return _post(supabaseUrl, 'list_users', {}, bearerToken: bearerToken);
  }

  /// Set a user's permission flags (server admin only; not your own).
  Future<APIResponse> setUserPermissions(
    String supabaseUrl, {
    String? bearerToken,
    required String userId,
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  }) {
    return _post(supabaseUrl, 'set_user_permissions', {
      'user_id': userId,
      'is_server_admin': ?isServerAdmin,
      'is_channel_manager': ?isChannelManager,
      'can_create_tokens': ?canCreateTokens,
    }, bearerToken: bearerToken);
  }

  // ──────────────────────────────────────────────────────────
  // Channels
  // ──────────────────────────────────────────────────────────

  /// Create a new channel.
  Future<APIResponse> createChannel(
    String supabaseUrl, {
    String? bearerToken,
    required String name,
    required String channelType,
  }) {
    return _post(supabaseUrl, 'create_channel', {
      'name': name,
      'channel_type': channelType,
    }, bearerToken: bearerToken);
  }

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

  /// Delete a channel (requires channel manager).
  Future<APIResponse> deleteChannel(
    String supabaseUrl,
    String channelId, {
    String? bearerToken,
  }) {
    return _post(supabaseUrl, 'delete_channel', {
      'channel_id': channelId,
    }, bearerToken: bearerToken);
  }

  /// Persistently mute/unmute/deafen/undeafen a user (requires channel
  /// manager or server admin). State is stored server-side and enforced in
  /// LiveKit token grants, so it survives rejoins and can't be self-reverted.
  Future<APIResponse> moderateUser(
    String supabaseUrl, {
    String? bearerToken,
    required String userId,
    bool? isMuted,
    bool? isDeafened,
  }) {
    return _post(supabaseUrl, 'moderate_user', {
      'user_id': userId,
      'is_muted': ?isMuted,
      'is_deafened': ?isDeafened,
    }, bearerToken: bearerToken);
  }
}
