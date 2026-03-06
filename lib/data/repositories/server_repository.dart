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

  /// Create a new server.
  Future<APIResponse> createServer(
    String supabaseUrl, {
    required String name,
    String? iconUrl,
    required String livekitUrl,
    required String livekitApiKey,
    required String livekitSecretKey,
  }) {
    return _post(supabaseUrl, 'create_server', {
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

  // ──────────────────────────────────────────────────────────
  // Users & Tokens
  // ──────────────────────────────────────────────────────────

  /// Join a server — creates a user account and links it to the token.
  Future<APIResponse> joinServer(
    String supabaseUrl,
    String token, {
    required String username,
    required String displayName,
  }) {
    return _post(supabaseUrl, 'join_server', {
      'token': token,
      'username': username,
      'display_name': displayName,
    });
  }

  /// Check whether a username is available on the given server.
  Future<APIResponse> isUsernameAvailable(String supabaseUrl, String username) {
    return _post(supabaseUrl, 'is_username_available', {'username': username});
  }

  /// Create an access/invite token with optional permissions.
  Future<APIResponse> createAccessToken(
    String supabaseUrl,
    String callerToken, {
    bool isServerAdmin = false,
    bool isChannelManager = false,
    bool canCreateTokens = false,
  }) {
    return _post(supabaseUrl, 'create_access_token', {
      'token': callerToken,
      'is_server_admin': isServerAdmin,
      'is_channel_manager': isChannelManager,
      'can_create_tokens': canCreateTokens,
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
    String channelId,
  ) {
    return _post(supabaseUrl, 'get_channel_token', {
      'token': token,
      'channel_id': channelId,
    });
  }

  /// Mute or unmute a participant for everyone in a channel (requires is_channel_manager).
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
