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
    Map<String, dynamic> body,
  ) async {
    try {
      final uri = Uri.parse('$supabaseUrl/functions/v1/$functionName');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
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
    return APIResponse.error(data['error'] ?? 'Unknown error');
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
  Future<APIResponse> getServerDetails(String supabaseUrl, String token) {
    return _post(supabaseUrl, 'get_server_details', {'token': token});
  }

  /// Update server details (admin only).
  Future<APIResponse> updateServer(
    String supabaseUrl,
    String token, {
    String? name,
    String? iconUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
  }) {
    return _post(supabaseUrl, 'update_server', {
      'token': token,
      if (name != null) 'name': name,
      if (iconUrl != null) 'icon_url': iconUrl,
      if (livekitApiKey != null) 'livekit_api_key': livekitApiKey,
      if (livekitSecretKey != null) 'livekit_secret_key': livekitSecretKey,
    });
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
  }) {
    return _post(supabaseUrl, 'get_challenge', {
      'public_key': publicKey,
    });
  }

  /// Verify a signed challenge to authenticate and get full server context.
  Future<APIResponse> verifyChallenge(
    String supabaseUrl, {
    required String publicKey,
    required String nonce,
    required String signature,
  }) {
    return _post(supabaseUrl, 'verify_challenge', {
      'public_key': publicKey,
      'nonce': nonce,
      'signature': signature,
    });
  }

  /// Rotate Ed25519 key: proves ownership with old key, replaces with new key.
  Future<APIResponse> rotateKey(
    String supabaseUrl, {
    required String oldPublicKey,
    required String newPublicKey,
    required String signature,
  }) {
    return _post(supabaseUrl, 'rotate_key', {
      'old_public_key': oldPublicKey,
      'new_public_key': newPublicKey,
      'signature': signature,
    });
  }

  /// Check whether a username is available on the given server.
  Future<APIResponse> isUsernameAvailable(String supabaseUrl, String username) {
    return _post(supabaseUrl, 'is_username_available', {'username': username});
  }

  /// Create an invite code with optional permissions.
  /// [maxUses] null = unlimited, 1 = single-use.
  Future<APIResponse> createInvite(
    String supabaseUrl,
    String callerToken, {
    bool isServerAdmin = false,
    bool isChannelManager = false,
    bool canCreateTokens = false,
    int? maxUses = 1,
  }) {
    return _post(supabaseUrl, 'create_invite', {
      'token': callerToken,
      'is_server_admin': isServerAdmin,
      'is_channel_manager': isChannelManager,
      'can_create_tokens': canCreateTokens,
      'max_uses': maxUses,
    });
  }

  // ──────────────────────────────────────────────────────────
  // Channels
  // ──────────────────────────────────────────────────────────

  /// Create a new channel.
  Future<APIResponse> createChannel(
    String supabaseUrl,
    String token, {
    required String name,
    required String channelType,
  }) {
    return _post(supabaseUrl, 'create_channel', {
      'token': token,
      'name': name,
      'channel_type': channelType,
    });
  }

  /// Get a LiveKit JWT for joining a channel.
  Future<APIResponse> getChannelToken(
    String supabaseUrl,
    String token,
    String channelId, {
    bool screenShare = false,
  }) {
    return _post(supabaseUrl, 'get_channel_token', {
      'token': token,
      'channel_id': channelId,
      'screen_share': screenShare,
    });
  }

  /// Delete a channel (requires channel manager).
  Future<APIResponse> deleteChannel(
    String supabaseUrl,
    String token,
    String channelId,
  ) {
    return _post(supabaseUrl, 'delete_channel', {
      'token': token,
      'channel_id': channelId,
    });
  }

  /// Mute or unmute a participant (requires channel manager).
  Future<APIResponse> muteParticipant(
    String supabaseUrl,
    String token, {
    required String channelId,
    required String participantIdentity,
    required bool muted,
  }) {
    return _post(supabaseUrl, 'mute_participant', {
      'token': token,
      'channel_id': channelId,
      'participant_identity': participantIdentity,
      'muted': muted,
    });
  }
}
