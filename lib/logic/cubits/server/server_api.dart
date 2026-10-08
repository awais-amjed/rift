part of 'server_cubit.dart';

/// A server itself: creating one, its listing token, its settings and
/// details, and leaving it.
mixin _ServerApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  SessionRepository get _session;
  void removeServer(String serverId);
  void noteServerGone({required String supabaseUrl, required String id});

  /// Ping the `server_events` doorbell after a structural change (channel
  /// create/delete, …) so other members refresh in realtime.
  void Function(String serverId)? get _onServerEvent;

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
    int? storageUsed,
    bool clearUser = false,
  });

  /// Implemented by [ServerCubit]: land a whole `get_server_details()` reply.
  void applyServerDetails(
    String serverId,
    ServerDetails details, {
    String? token,
  });

  /// Implemented by [ServerCubit]: the server a call is about — the one the
  /// caller named, or the selection when it named none.
  Server? _target(String? serverId);
  String _noTarget(String? serverId);

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

  /// The default voice region's address and key, which are the *server's*
  /// LiveKit URL and key pair.
  ///
  /// Written through `update_server` rather than through the node, because
  /// `servers.livekit_url` and `server_secrets` are where they live, and a
  /// trigger carries the address into the default node. Writing the node
  /// instead would leave the two disagreeing, and the column is what an older
  /// client still reads. Each is sent only if given, and `update_server`
  /// leaves alone what it isn't sent. The other regions are `VoiceRegionsApi`.
  ///
  /// Ends like those calls — the probe's measurement thrown away, the server
  /// re-read — because the default node's row may just have changed
  /// underneath us and the copy held here would still name the old box.
  Future<({bool success, String? error})> updateDefaultVoiceRegion({
    String? url,
    String? apiKey,
    String? secret,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }
    if (url == null && apiKey == null && secret == null) {
      return (success: true, error: null);
    }

    final result = await updateServerDetails(
      livekitUrl: url,
      livekitApiKey: apiKey,
      livekitSecretKey: secret,
      serverId: server.id,
    );
    if (!result.success) return result;

    _session.regionProbe.invalidate(server.id);
    await refreshServerDetails();
    return (success: true, error: null);
  }

  /// Refresh the channel list and other details for [serverId], or for the
  /// selected server.
  ///
  /// Coalesced, because one structural change reaches a member more than
  /// once — the database announces it, and the member who made it also
  /// re-reads straight after their own write. See [CoalescedRefresh] for why
  /// the second read still happens rather than being dropped.
  late final CoalescedRefresh<({bool success, String? error})> _details =
      CoalescedRefresh(_fetchServerDetails);

  ///
  /// A named server other than the selected one is read straight away: it is
  /// a settings page acting on it, once, not the stream of doorbells the
  /// selected one hears.
  Future<({bool success, String? error})> refreshServerDetails({
    String? serverId,
  }) {
    if (serverId == null || serverId == state.selectedServer?.id) {
      return _details();
    }
    final server = state.serverById(serverId);
    if (server == null) {
      return Future.value((success: false, error: _noTarget(serverId)));
    }
    return _fetchDetailsOf(server);
  }

  Future<({bool success, String? error})> _fetchServerDetails() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }
    return _fetchDetailsOf(server);
  }

  Future<({bool success, String? error})> _fetchDetailsOf(Server server) async {
    final response = await _callFor(
      server,
      (token) => _repository.getServerDetails(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );

    // The server's row is invisible to somebody it no longer knows — our own
    // row is what scopes every read — so "not found" from a server we were on
    // yesterday means it was deleted, or we were removed. Either way there is
    // nothing left here to refresh, and keeping the rail chip would leave a
    // server nobody can leave.
    if (!response.success && response.error == ServerDb.serverGone) {
      // The same note the selection path takes: without it the auto-backup
      // this removal triggers merges the cloud's copy back in.
      noteServerGone(supabaseUrl: server.supabaseUrl, id: server.id);
      removeServer(server.id);
      emit(
        state.copyWith(
          notice: Notice.info(
            'No longer on ${server.name}',
            'The server was deleted, or you were removed from it.',
          ),
        ),
      );
      return (success: false, error: response.error);
    }

    if (response.success) {
      final data = response.data as Map<String, dynamic>;
      applyServerDetails(server.id, ServerDetails.fromJson(data));
      return (success: true, error: null);
    } else {
      return (
        success: false,
        error: response.error ?? 'Failed to refresh server details',
      );
    }
  }
}
