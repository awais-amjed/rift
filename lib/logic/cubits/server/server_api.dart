part of 'server_cubit.dart';

mixin _ServerApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  /// The selected server's anon key, id, and the caller's own user id — what a
  /// direct PostgREST call needs on top of a bearer token.
  String get _anonKey;
  String get _serverId;
  String get _userId;

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
  }) => _callWithAutoRefresh(
    (token) => _repository.getChannelToken(
      state.selectedServer!.supabaseUrl,
      channelId,
      screenShare: screenShare,
      bearerToken: token,
    ),
  );

  /// Last fetched member list, keyed by user id — warmed by [listMembers].
  ///
  /// Lets any surface resolve a user id to their profile (notably
  /// `chat_public_key`, needed to open a DM) without another round trip. Not
  /// authoritative: [findMember] refetches on a miss.
  final Map<String, ServerMember> _memberCache = {};

  /// A member by user id, fetching the list once if we haven't got them.
  /// Null when they aren't a member of the selected server.
  Future<ServerMember?> findMember(String userId) async {
    final cached = _memberCache[userId];
    if (cached != null) return cached;
    final result = await listMembers();
    if (!result.success) return null;
    return _memberCache[userId];
  }

  /// Fetch the full member list for the selected server.
  Future<({bool success, List<ServerMember>? members, String? error})>
  listMembers() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, members: null, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.listUsers(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
      ),
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
    _memberCache
      ..clear()
      ..addEntries(members.map((m) => MapEntry(m.id, m)));
    return (success: true, members: members, error: null);
  }

  /// Set a member's permission flags (server admin only).
  Future<APIResponse> setUserPermissions({
    required String userId,
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  }) => _callWithAutoRefresh(
    (token) => _repository.setUserPermissions(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
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
  }) => _callWithAutoRefresh(
    (token) => _repository.moderateUser(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      bearerToken: token,
      userId: userId,
      isMuted: isMuted,
      isDeafened: isDeafened,
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
        anonKey: _anonKey,
        serverId: _serverId,
        userId: _userId,
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
        anonKey: _anonKey,
        serverId: _serverId,
        bearerToken: token,
        name: name,
        channelType: channelType,
      ),
    );

    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to create channel',
      );
    }

    // Refresh our own channel list to include the newly created one, and ping
    // the server_events doorbell so other members refresh in realtime.
    await refreshServerDetails();
    _onServerEvent?.call();
    return (success: true, error: null);
  }

  /// Rename a channel in the selected server (channel manager only).
  Future<({bool success, String? error})> renameChannel({
    required String channelId,
    required String name,
  }) => _changeChannel(
    (server, token) => _repository.renameChannel(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      name: name,
    ),
    failure: 'Failed to rename channel',
  );

  /// Delete a channel in the selected server (channel manager only). Anyone in
  /// its call is dropped — see [ServerRepository.deleteChannel].
  Future<({bool success, String? error})> deleteChannel(String channelId) =>
      _changeChannel(
        (server, token) => _repository.deleteChannel(
          server.supabaseUrl,
          channelId,
          bearerToken: token,
        ),
        failure: 'Failed to delete channel',
      );

  /// Runs a channel mutation, then brings everyone's sidebar in line: our own
  /// list directly, and other members' through the `server_events` doorbell.
  /// They also hear it from Realtime on `channels`; the ping is what makes it
  /// immediate rather than a beat later.
  Future<({bool success, String? error})> _changeChannel(
    Future<APIResponse> Function(Server server, String token) call, {
    required String failure,
  }) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server selected');

    final response = await _callWithAutoRefresh((token) => call(server, token));
    if (!response.success) {
      return (success: false, error: response.error ?? failure);
    }

    await refreshServerDetails();
    _onServerEvent?.call();
    return (success: true, error: null);
  }

  /// Update the selected server's settings (admin only). Only non-null fields
  /// are sent; the LiveKit API key / secret are write-only (never stored client
  /// side — the client only keeps [Server.livekitUrl]). On success the local
  /// name/icon/url are updated and the `server_events` doorbell is pinged so
  /// other members pick up the change.
  Future<({bool success, String? error})> updateServerDetails({
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.updateServer(
        server.supabaseUrl,
        bearerToken: token,
        name: name,
        iconUrl: iconUrl,
        livekitUrl: livekitUrl,
        livekitApiKey: livekitApiKey,
        livekitSecretKey: livekitSecretKey,
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
    );
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
