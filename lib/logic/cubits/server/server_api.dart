part of 'server_cubit.dart';

mixin _ServerApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  /// The selected server's anon key — what a direct PostgREST call needs on top
  /// of a bearer token, for the calls that are about the current server.
  String get _anonKey;

  /// Ping the `server_events` doorbell after a structural change (channel
  /// create/delete, …) so other members refresh in realtime.
  void Function(String serverId)? get _onServerEvent;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  Future<APIResponse> _callFor(
    Server server,
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
    ServerLimits? limits,
    bool clearUser = false,
  });

  /// Implemented by [ServerCubit]: the server a call is about — the one the
  /// caller named, or the selection when it named none.
  Server? _target(String? serverId);
  String _noTarget(String? serverId);

  // ──────────────────────────────────────────────────────────
  // API Operations
  // ──────────────────────────────────────────────────────────

  /// Returns a LiveKit JWT for [channelId]. Token refresh is handled automatically.
  Future<APIResponse> getChannelToken(
    String channelId, {
    bool screenShare = false,
  }) => _callWithAutoRefresh(
    (token) => _repository.getChannelToken(
      state.selectedServer!.supabaseUrl,
      channelId,
      screenShare: screenShare,
      bearerToken: token,
    ),
  );

  /// Moves a member into another voice channel (requires channel manager or
  /// server admin). They have to be in a call for there to be anything to move.
  Future<APIResponse> moveUser({
    required String userId,
    required String channelId,
  }) => _callWithAutoRefresh(
    (token) => _repository.moveUser(
      state.selectedServer!.supabaseUrl,
      bearerToken: token,
      userId: userId,
      channelId: channelId,
    ),
  );

  /// Who is in which voice channel on the selected server, straight from
  /// LiveKit: `{roster: {userId: channelId}}`.
  Future<APIResponse> voiceRoster() => _callWithAutoRefresh(
    (token) => _repository.voiceRoster(
      state.selectedServer!.supabaseUrl,
      bearerToken: token,
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

  /// Create a plain invite code for [serverId], or for the selected server.
  Future<({bool success, String? inviteCode, String? error})> createInvite({
    int? maxUses = 1,
    int? expiresInSeconds,
    String? serverId,
  }) async {
    final server = _target(serverId);
    if (server == null) {
      return (success: false, inviteCode: null, error: _noTarget(serverId));
    }

    final response = await _callFor(
      server,
      (token) => _repository.createInvite(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        serverId: server.id,
        userId: server.user?.id ?? '',
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
  Future<({bool success, String? error, String? serverId, String? serverName})>
  validateInvite(String supabaseUrl, String inviteCode) async {
    return (success: true, error: null, serverId: null, serverName: null);
  }

  /// Update the settings of [serverId], or of the selected server (admin only).
  /// Only non-null fields are sent; the LiveKit API key / secret are write-only
  /// (never stored client side — the client only keeps [Server.livekitUrl]). On
  /// success the local name/icon/url are updated and the `server_events`
  /// doorbell is pinged so other members pick up the change.
  Future<({bool success, String? error})> updateServerDetails({
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
    ServerLimits? limits,
    String? serverId,
  }) async {
    final server = _target(serverId);
    if (server == null) {
      return (success: false, error: _noTarget(serverId));
    }

    final response = await _callFor(
      server,
      (token) => _repository.updateServer(
        server.supabaseUrl,
        bearerToken: token,
        name: name,
        iconUrl: iconUrl,
        livekitUrl: livekitUrl,
        livekitApiKey: livekitApiKey,
        livekitSecretKey: livekitSecretKey,
        limits: limits,
      ),
    );

    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to update server',
      );
    }

    final data = (response.data as Map?)?.cast<String, dynamic>() ?? const {};
    updateServer(
      server.id,
      name: data['name'] as String? ?? name,
      iconUrl: data['icon_url'] as String?,
      livekitUrl: data['livekit_url'] as String? ?? livekitUrl,
      // Read back rather than echoed: the endpoint returns the whole row, so a
      // limit the server clamped or refused shows up here as what was stored.
      limits: data.isEmpty ? limits : ServerLimits.fromJson(data),
    );
    _onServerEvent?.call(server.id);
    return (success: true, error: null);
  }

  /// Refresh the channel list and other details for the selected server.
  Future<({bool success, String? error})> refreshServerDetails() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.getServerDetails(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
      ),
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
      final user = rawUser != null
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
