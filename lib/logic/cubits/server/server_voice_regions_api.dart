part of 'server_cubit.dart';

/// Adding, renaming and removing the LiveKit nodes a server holds calls on.
///
/// All three end the same way — refresh the server so the node list and every
/// channel's pin come back in step — which is the seam this shares with
/// [_ServerChannelsApiMixin] and the reason it is its own file rather than
/// three more methods on the voice API next door.
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
  Future<({bool success, String? error})> refreshServerDetails();
  Future<({bool success, String? error})> updateServerDetails({
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
    ServerLimits? limits,
    String? serverId,
  });

  Future<({bool success, String? error})> addVoiceRegion({
    required String label,
    required String url,
  }) => _changeVoiceRegion(
    (server, token) => _repository.addVoiceRegion(
      server.supabaseUrl,
      serverId: server.id,
      label: label,
      url: url,
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

  /// The default region's address, which is the *server's* LiveKit URL.
  ///
  /// Written through `update_server` rather than through the node, because
  /// `servers.livekit_url` is where that address lives and a trigger carries
  /// it into the default node. Writing the node instead would leave the two
  /// disagreeing, and the column is what an older client still reads.
  ///
  /// Ends like the three above it — the probe's measurement thrown away, the
  /// server re-read — because the default node's row has just changed
  /// underneath us and the copy held here still names the old box.
  Future<({bool success, String? error})> updateDefaultVoiceRegion({
    required String url,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final result = await updateServerDetails(
      livekitUrl: url,
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

    final response = await _callWithAutoRefresh(
      (token) => call(server, token),
    );
    if (!response.success) {
      return (success: false, error: response.error ?? failure);
    }

    _regionProbe.invalidate(server.id);
    await refreshServerDetails();
    return (success: true, error: null);
  }
}
