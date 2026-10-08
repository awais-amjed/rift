part of 'server_cubit.dart';

/// Adding, renaming and removing the LiveKit nodes a server holds calls on.
///
/// All three end the same way — refresh the server so the node list and every
/// channel's pin come back in step — which is the seam this shares with
/// `ChannelsApi` and the reason it is its own file rather than three more
/// methods on the voice API next door.
///
/// The probe's cached measurement is thrown away on every change: it is keyed
/// on the set of nodes, so an added or removed one has to be measured before
/// the next call can be sent anywhere sensible.
mixin _ServerVoiceRegionsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  VoiceRegionProbe get _regionProbe;
  String get _anonKey;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Both implemented by [_ServerApiMixin]. The update is repeated whole
  /// rather than narrowed to the one field sent below: a declaration with
  /// fewer named parameters is not something the real one can override.
  Future<({bool success, String? error})> refreshServerDetails({
    String? serverId,
  });
  Future<({bool success, String? error})> updateServerDetails({
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
    ServerLimits? limits,
    String? serverId,
  });

  /// Adds a region, with the LiveKit key pair it signs with — both required,
  /// because a region without one would fall back to the server's key.
  Future<({bool success, String? error})> addVoiceRegion({
    required String label,
    required String url,
    required String apiKey,
    required String secret,
  }) => _changeVoiceRegion(
    (server, token) => _repository.addVoiceRegion(
      server.supabaseUrl,
      label: label,
      url: url,
      apiKey: apiKey,
      secret: secret,
      anonKey: _anonKey,
      bearerToken: token,
    ),
    failure: 'Failed to add the region',
  );

  Future<({bool success, String? error})> updateVoiceRegion({
    required String nodeId,
    String? label,
    String? url,
  }) => _changeVoiceRegion(
    (server, token) => _repository.updateVoiceRegion(
      server.supabaseUrl,
      nodeId,
      label: label,
      url: url,
      anonKey: _anonKey,
      bearerToken: token,
    ),
    failure: 'Failed to change the region',
  );

  /// Replaces the key pair a region signs with — a rotation, one box at a
  /// time.
  ///
  /// Its own call rather than part of [updateVoiceRegion], because it writes a
  /// different table through a different door: the node row is an ordinary
  /// table write under a policy, and the key is an RPC that checks the caller
  /// because the table it writes has no policy at all.
  Future<({bool success, String? error})> setVoiceRegionCredentials({
    required String nodeId,
    required String apiKey,
    required String secret,
  }) => _changeVoiceRegion(
    (server, token) => _repository.setVoiceRegionCredentials(
      server.supabaseUrl,
      nodeId,
      apiKey: apiKey,
      secret: secret,
      anonKey: _anonKey,
      bearerToken: token,
    ),
    failure: 'Failed to change the region\'s credentials',
  );

  /// The default region's address and key, which are the *server's* LiveKit
  /// URL and key pair.
  ///
  /// Written through `update_server` rather than through the node, because
  /// `servers.livekit_url` and `server_secrets` are where they live, and a
  /// trigger carries the address into the default node. Writing the node
  /// instead would leave the two disagreeing, and the column is what an older
  /// client still reads. Each is sent only if given, and `update_server`
  /// leaves alone what it isn't sent.
  ///
  /// Ends like the calls above it — the probe's measurement thrown away, the
  /// server re-read — because the default node's row may just have changed
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

    _regionProbe.invalidate(server.id);
    await refreshServerDetails();
    return (success: true, error: null);
  }

  Future<({bool success, String? error})> deleteVoiceRegion(String nodeId) =>
      _changeVoiceRegion(
        (server, token) => _repository.deleteVoiceRegion(
          server.supabaseUrl,
          nodeId,
          anonKey: _anonKey,
          bearerToken: token,
        ),
        failure: 'Failed to remove the region',
      );

  Future<({bool success, String? error})> _changeVoiceRegion(
    Future<APIResponse> Function(Server server, String token) call, {
    required String failure,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh((token) => call(server, token));
    if (!response.success) {
      return (success: false, error: response.error ?? failure);
    }

    _regionProbe.invalidate(server.id);
    await refreshServerDetails();
    return (success: true, error: null);
  }
}
