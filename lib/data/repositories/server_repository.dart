import 'dart:convert';

import 'package:http/http.dart' as http;

import '../classes/api_response.dart';

/// Repository for all Supabase Edge Function API calls.
class ServerRepository {
  // ──────────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────────

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    try {
      final uri = Uri.parse('$supabaseUrl/functions/v1/$functionName');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
        },
        body: jsonEncode(body),
      );
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      return _fromSupabaseCF(result);
    } catch (e) {
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
    return _post(supabaseUrl, 'get_server_details', {}, bearerToken: bearerToken);
  }

  /// Update server details (admin only).
  Future<APIResponse> updateServer(
    String supabaseUrl, {
    String? bearerToken,
    String? name,
    String? iconUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
  }) {
    return _post(
      supabaseUrl,
      'update_server',
      {
        if (name != null) 'name': name,
        if (iconUrl != null) 'icon_url': iconUrl,
        if (livekitApiKey != null) 'livekit_api_key': livekitApiKey,
        if (livekitSecretKey != null) 'livekit_secret_key': livekitSecretKey,
      },
      bearerToken: bearerToken,
    );
  }

  // ──────────────────────────────────────────────────────────
  // Registration & Auth
  // ──────────────────────────────────────────────────────────

  /// Register on a server using an invite code + cryptographic identity.
  /// Used for both initial server setup (admin) and joining via invite.
  /// Returns full server context including a new auth token.
  Future<APIResponse> register(
    String supabaseUrl, {
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
    });
  }

  /// Request a challenge nonce for Ed25519 authentication.
  Future<APIResponse> getChallenge(
    String supabaseUrl, {
    required String publicKey,
    required String serverId,
  }) {
    return _post(supabaseUrl, 'get_challenge', {
      'public_key': publicKey,
      'server_id': serverId,
    });
  }

  /// Verify a signed challenge to authenticate and get full server context.
  ///
  /// [host] is the hostname the client used to derive its Ed25519 identity
  /// (i.e. `Uri.parse(supabaseUrl).host`). Sending it explicitly lets the
  /// server reconstruct the signed message without relying on the Host header
  /// (which reverse proxies may rewrite).
  Future<APIResponse> verifyChallenge(
    String supabaseUrl, {
    required String publicKey,
    required String nonce,
    required String signature,
    required String host,
    required String serverId,
  }) {
    return _post(supabaseUrl, 'verify_challenge', {
      'public_key': publicKey,
      'nonce': nonce,
      'signature': signature,
      'host': host,
      'server_id': serverId,
    });
  }

  /// Rotate Ed25519 key: proves ownership with old key, replaces with new key.
  ///
  /// [nonce] is a server-issued rotation challenge obtained via [getChallenge].
  /// [host] is the hostname used for key derivation — same note as [verifyChallenge].
  Future<APIResponse> rotateKey(
    String supabaseUrl, {
    required String oldPublicKey,
    required String newPublicKey,
    required String nonce,
    required String signature,
    required String host,
    required String serverId,
  }) {
    return _post(supabaseUrl, 'rotate_key', {
      'old_public_key': oldPublicKey,
      'new_public_key': newPublicKey,
      'nonce': nonce,
      'signature': signature,
      'host': host,
      'server_id': serverId,
    });
  }

  /// Check whether a username is available on the given server.
  Future<APIResponse> isUsernameAvailable(String supabaseUrl, String username) {
    return _post(supabaseUrl, 'is_username_available', {'username': username});
  }

  /// Create an invite code with optional permissions and constraints.
  /// [maxUses] null = unlimited, 1 = single-use (default).
  /// [expiresInSeconds] null = never expires.
  Future<APIResponse> createInvite(
    String supabaseUrl, {
    String? bearerToken,
    bool isServerAdmin = false,
    bool isChannelManager = false,
    bool canCreateTokens = false,
    int? maxUses = 1,
    int? expiresInSeconds,
  }) {
    return _post(
      supabaseUrl,
      'create_invite',
      {
        'is_server_admin': isServerAdmin,
        'is_channel_manager': isChannelManager,
        'can_create_tokens': canCreateTokens,
        'max_uses': maxUses,
        if (expiresInSeconds != null) 'expires_in_seconds': expiresInSeconds,
      },
      bearerToken: bearerToken,
    );
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
    return _post(
      supabaseUrl,
      'create_channel',
      {'name': name, 'channel_type': channelType},
      bearerToken: bearerToken,
    );
  }

  /// Get a LiveKit JWT for joining a channel.
  Future<APIResponse> getChannelToken(
    String supabaseUrl,
    String channelId, {
    bool screenShare = false,
    String? bearerToken,
  }) {
    return _post(
      supabaseUrl,
      'get_channel_token',
      {'channel_id': channelId, 'screen_share': screenShare},
      bearerToken: bearerToken,
    );
  }

  /// Delete a channel (requires channel manager).
  Future<APIResponse> deleteChannel(
    String supabaseUrl,
    String channelId, {
    String? bearerToken,
  }) {
    return _post(
      supabaseUrl,
      'delete_channel',
      {'channel_id': channelId},
      bearerToken: bearerToken,
    );
  }

  /// Mute or unmute a participant (requires channel manager).
  Future<APIResponse> muteParticipant(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    required String participantIdentity,
    required bool muted,
  }) {
    return _post(
      supabaseUrl,
      'mute_participant',
      {
        'channel_id': channelId,
        'participant_identity': participantIdentity,
        'muted': muted,
      },
      bearerToken: bearerToken,
    );
  }
}
