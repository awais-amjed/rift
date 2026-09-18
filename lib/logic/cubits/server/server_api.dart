part of 'server_cubit.dart';

mixin _ServerApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  void removeServer(String serverId);

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
    bool soundShare = false,
  }) => _callWithAutoRefresh(
    (token) => _repository.getChannelToken(
      state.selectedServer!.supabaseUrl,
      channelId,
      screenShare: screenShare,
      soundShare: soundShare,
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

  /// Disconnects a member from the voice channel they're in (requires channel
  /// manager or server admin). They have to be in a call for there to be
  /// anything to end, and nothing stops them rejoining — see `kick_user`.
  Future<APIResponse> kickUser({required String userId}) =>
      _callWithAutoRefresh(
        (token) => _repository.kickUser(
          state.selectedServer!.supabaseUrl,
          bearerToken: token,
          userId: userId,
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
  /// A one-time token proving an admin of [serverId] wants it listed.
  ///
  /// Handed to central, which redeems it against this server's own domain
  /// before writing a directory entry — see `publish_server` there.
  ///
  /// Returns the server's own reason on failure rather than a bare null. It
  /// used to return null for everything, and every caller said the same thing
  /// — "only a server admin can list this server publicly" — so an endpoint
  /// that was failing to boot, a server that was unreachable and a genuine
  /// refusal all arrived as an accusation that the admin was not an admin.
  Future<({String? token, String? error})> listingToken({
    String? serverId,
  }) async {
    final server = _target(serverId);
    if (server == null) {
      return (token: null, error: 'That server is not open here any more.');
    }

    final response = await _callFor(
      server,
      (token) =>
          _repository.listingToken(server.supabaseUrl, bearerToken: token),
    );
    if (!response.success) {
      return (token: null, error: response.error?.toString());
    }

    final token = (response.data as Map<String, dynamic>?)?['token'] as String?;
    return token == null
        ? (token: null, error: 'This server did not return a listing token.')
        : (token: token, error: null);
  }

  Future<({bool success, String? inviteCode, String? error})> createInvite({
    int? maxUses = 1,
    int? expiresInSeconds,
    String? serverId,
    bool isBot = false,
    String? roleId,
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
        isBot: isBot,
        roleId: roleId,
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

  /// Read an invite link and ask its server what it opens, without using it.
  ///
  /// The first of the two join steps. A link that does not parse is refused
  /// here, in words; one that parses is put to the server, which answers with
  /// the name — or with why not, which is the same answer registration would
  /// have given a screen later, after a username had been typed for nothing.
  Future<({ResolvedInvite? invite, String? error})> resolveInvite(
    String rawLink,
  ) async {
    final link = InviteLink.parse(rawLink);
    if (link == null) {
      return (
        invite: null,
        error:
            "That doesn't look like a complete invite link. Ask the server "
            'admin for a new one.',
      );
    }
    final resolved = await _repository.resolveInvite(
      link.serverUrl,
      link.inviteCode,
    );
    if (!resolved.success || resolved.serverId == null) {
      return (
        invite: null,
        error: resolved.error ?? 'That invite cannot be used any more.',
      );
    }
    return (
      invite: ResolvedInvite(
        serverUrl: link.serverUrl,
        inviteCode: link.inviteCode,
        serverId: resolved.serverId!,
        serverName: resolved.serverName ?? link.serverUrl,
      ),
      error: null,
    );
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
  ///
  /// Coalesced, because one structural change reaches a member more than
  /// once — the database announces it, and the member who made it also
  /// re-reads straight after their own write. See [CoalescedRefresh] for why
  /// the second read still happens rather than being dropped.
  late final CoalescedRefresh<({bool success, String? error})> _details =
      CoalescedRefresh(_fetchServerDetails);

  Future<({bool success, String? error})> refreshServerDetails() => _details();

  Future<({bool success, String? error})> _fetchServerDetails() async {
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

    // The server's row is invisible to somebody it no longer knows — our own
    // row is what scopes every read — so "not found" from a server we were on
    // yesterday means it was deleted, or we were removed. Either way there is
    // nothing left here to refresh, and keeping the rail chip would leave a
    // server nobody can leave.
    if (!response.success && response.error == ServerDb.serverGone) {
      removeServer(server.id);
      HelperMethods.showToast(
        title: 'No longer on ${server.name}',
        description: 'The server was deleted, or you were removed from it.',
      );
      return (success: false, error: response.error);
    }

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

      // Only when the response carries them. `ServerLimits.fromJson` fills in
      // defaults for anything missing, which is right for a real payload and
      // wrong for one that never mentioned limits — it would quietly reset an
      // operator's caps to the defaults. The banned-member reply is exactly
      // that shape.
      final limits = data.containsKey('max_attachment_bytes')
          ? ServerLimits.fromJson(data)
          : null;

      updateServer(
        server.id,
        // The identity of the server, not just its contents. These were
        // fetched and then dropped on the floor, so a rename, a new icon or a
        // moved LiveKit URL reached only the client that made the change —
        // everyone else kept the old one until they rejoined. `copyWith`
        // leaves a null alone, so a reply that omits them changes nothing.
        name: data['name'] as String?,
        iconUrl: data['icon_url'] as String?,
        livekitUrl: data['livekit_url'] as String?,
        limits: limits,
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
