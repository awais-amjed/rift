part of 'server_cubit.dart';

mixin _ServerApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  /// Ping the `server_events` doorbell after a structural change (channel
  /// create/delete, …) so other members refresh in realtime.
  void Function()? get _onServerEvent;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  void updateServer(
    String serverId, {
    String? name,
    String? iconUrl,
    String? supabaseKey,
    String? livekitUrl,
    String? token,
    String? keyVersion,
    ServerUser? user,
    List<Channel>? channels,
    bool clearUser = false,
  });

  // ──────────────────────────────────────────────────────────
  // API Operations
  // ──────────────────────────────────────────────────────────

  /// Returns a LiveKit JWT for [channelId]. Token refresh is handled automatically.
  Future<APIResponse> getChannelToken(
    String channelId, {
    bool screenShare = false,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.getChannelToken(
          state.selectedServer!.supabaseUrl,
          channelId,
          screenShare: screenShare,
          bearerToken: token,
        ),
      );

  /// Fetch the full member list for the selected server.
  Future<({bool success, List<ServerMember>? members, String? error})>
      listMembers() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, members: null, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) =>
          _repository.listUsers(server.supabaseUrl, bearerToken: token),
    );

    if (!response.success) {
      return (
        success: false,
        members: null,
        error: response.error ?? 'Failed to load members',
      );
    }

    final members = ((response.data['users'] as List<dynamic>?) ?? [])
        .map((u) => ServerMember.fromJson(u as Map<String, dynamic>))
        .toList();
    return (success: true, members: members, error: null);
  }

  /// Set a member's permission flags (server admin only).
  Future<APIResponse> setUserPermissions({
    required String userId,
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.setUserPermissions(
          state.selectedServer!.supabaseUrl,
          bearerToken: token,
          userId: userId,
          isServerAdmin: isServerAdmin,
          isChannelManager: isChannelManager,
          canCreateTokens: canCreateTokens,
        ),
      );

  /// Persistently mutes/deafens a user server-wide (requires channel
  /// manager or server admin).
  Future<APIResponse> moderateUser({
    required String userId,
    bool? isMuted,
    bool? isDeafened,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.moderateUser(
          state.selectedServer!.supabaseUrl,
          bearerToken: token,
          userId: userId,
          isMuted: isMuted,
          isDeafened: isDeafened,
        ),
      );

  /// Creates a new server. On success returns the single-use admin invite code.
  Future<({bool success, String? inviteCode, String? error})> createServer({
    required String supabaseUrl,
    required String serviceKey,
    required String name,
    String? iconUrl,
    required String livekitUrl,
    required String livekitApiKey,
    required String livekitSecretKey,
  }) async {
    final response = await _repository.createServer(
      supabaseUrl,
      serviceKey: serviceKey,
      name: name,
      iconUrl: iconUrl,
      livekitUrl: livekitUrl,
      livekitApiKey: livekitApiKey,
      livekitSecretKey: livekitSecretKey,
    );

    if (!response.success) {
      return (success: false, inviteCode: null, error: response.error);
    }

    final data = response.data as Map<String, dynamic>;
    final inviteCode = data['invite_code'] as String;
    return (success: true, inviteCode: inviteCode, error: null);
  }

  /// Create a plain invite code for the selected server.
  Future<({bool success, String? inviteCode, String? error})> createInvite({
    int? maxUses = 1,
    int? expiresInSeconds,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, inviteCode: null, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.createInvite(
        server.supabaseUrl,
        bearerToken: token,
        maxUses: maxUses,
        expiresInSeconds: expiresInSeconds,
      ),
    );

    if (response.success) {
      final inviteCode = response.data['invite_code'] as String;
      return (success: true, inviteCode: inviteCode, error: null);
    } else {
      return (
        success: false,
        inviteCode: null,
        error: response.error ?? 'Failed to generate invite',
      );
    }
  }

  /// Validate an invite code without registering a user.
  Future<
    ({
      bool success,
      String? error,
      String? serverId,
      String? serverName,
    })
  >
  validateInvite(String supabaseUrl, String inviteCode) async {
    return (
      success: true,
      error: null,
      serverId: null,
      serverName: null,
    );
  }

  /// Create a new channel in the selected server.
  Future<({bool success, String? error})> createChannel({
    required String name,
    required String channelType,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.createChannel(
        server.supabaseUrl,
        bearerToken: token,
        name: name,
        channelType: channelType,
      ),
    );

    if (!response.success) {
      return (success: false, error: response.error ?? 'Failed to create channel');
    }

    // Refresh our own channel list to include the newly created one, and ping
    // the server_events doorbell so other members refresh in realtime.
    await refreshServerDetails();
    _onServerEvent?.call();
    return (success: true, error: null);
  }

  /// Refresh the channel list and other details for the selected server.
  Future<({bool success, String? error})> refreshServerDetails() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.getServerDetails(server.supabaseUrl, bearerToken: token),
    );

    if (response.success) {
      final data = response.data as Map<String, dynamic>;
      final rawChannels = data['channels'] as List<dynamic>?;
      final channels =
          rawChannels
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];
      final supabaseKey = data['supabase_key'] as String?;
      final rawUser = data['user'];
      final user =
          rawUser != null
              ? ServerUser.fromJson(rawUser as Map<String, dynamic>)
              : null;

      updateServer(
        server.id,
        channels: channels,
        supabaseKey: supabaseKey,
        user: user,
      );
      return (success: true, error: null);
    } else {
      return (
        success: false,
        error: response.error ?? 'Failed to refresh server details',
      );
    }
  }
}

