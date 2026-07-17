part of 'server_cubit.dart';

mixin _ServerApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

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

  /// Create an invite code for the selected server.
  Future<({bool success, String? inviteCode, String? error})> createInvite({
    bool isServerAdmin = false,
    bool isChannelManager = false,
    bool canCreateTokens = false,
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
        isServerAdmin: isServerAdmin,
        isChannelManager: isChannelManager,
        canCreateTokens: canCreateTokens,
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

  /// Rotates the Ed25519 keypair for the selected server. Delegates crypto to
  /// [vaultCubit] and persists the new key version to state.
  Future<({bool success, String? error})> rotateServerKey(
    VaultCubit vaultCubit,
  ) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final result = await vaultCubit.rotateKey(supabaseUrl: server.supabaseUrl, serverId: server.id);

    if (!result.success) {
      return (success: false, error: result.error ?? 'Key rotation failed');
    }

    // Persist the new version so the next login derives the correct keypair.
    updateServer(server.id, keyVersion: result.newVersion);

    return (success: true, error: null);
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

    // Refresh the channel list to include the newly created one.
    await refreshServerDetails();
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

