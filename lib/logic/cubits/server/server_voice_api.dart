part of 'server_cubit.dart';

/// The server's side of a call: the LiveKit token to join one, who is in
/// which channel, and moving or removing somebody.
mixin _ServerVoiceApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  VoiceRegionProbe get _regionProbe;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Returns a LiveKit JWT for [channelId]. Token refresh is handled automatically.
  ///
  /// Measures which of the server's LiveKit nodes is nearest first, and sends
  /// that along — see [VoiceRegionProbe]. It costs nothing on the usual
  /// server, which has one node and therefore nothing to measure, and the
  /// answer is cached for half an hour on the servers that have several.
  /// A probe that fails is not an error: the server falls back to its default
  /// node, which is what every client did before there was anything to
  /// choose.
  Future<APIResponse> getChannelToken(
    String channelId, {
    bool screenShare = false,
    bool soundShare = false,
  }) async {
    final server = state.selectedServer;
    final preferred = server == null
        ? null
        : await _regionProbe.nearest(
            server.id,
            server.livekitNodes,
            load: state.regionLoad,
          );

    final response = await _callWithAutoRefresh(
      (token) => _repository.getChannelToken(
        state.selectedServer!.supabaseUrl,
        channelId,
        screenShare: screenShare,
        soundShare: soundShare,
        preferredNodeId: preferred,
        bearerToken: token,
      ),
    );

    // A refusal throws away the measurement, and that is the whole reason
    // this is not a plain `return`.
    //
    // The cache holds for half an hour, which is fine while every region is
    // up and wrong the moment one is not: a region that died after being
    // measured goes on being offered as the nearest, the server takes the
    // suggestion, and the join fails again — for as long as the cache lasts.
    // Found by killing a region under a live call: both clients dropped, and
    // Try again kept failing on the dead region while a fresh request naming
    // no preference reached the live one immediately.
    //
    // Re-measuring costs one request per region and a node that is down
    // cannot answer it, so the next attempt cannot suggest it.
    if (!response.success && server != null) {
      _regionProbe.invalidate(server.id);
    }
    return response;
  }

  /// Moves the call in [channelId] to [nodeId] (channel manager or admin).
  ///
  /// Everybody in it reconnects, which is a second or two of silence for the
  /// whole room — so this is a deliberate action, never a side effect of
  /// changing a setting on a channel nobody is in.
  Future<APIResponse> moveCall({
    required String channelId,
    required String nodeId,
  }) => _callWithAutoRefresh(
    (token) => _repository.moveCall(
      state.selectedServer!.supabaseUrl,
      channelId: channelId,
      nodeId: nodeId,
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
  /// The roster, and how busy each region is while we are asking.
  ///
  /// The load rides along because this call already fans out across every
  /// region — it is the one request that has to touch them all — so learning
  /// it costs nothing, and it is polled often enough to be current when a
  /// manager opens the picker.
  Future<APIResponse> voiceRoster() async {
    final asked = state.selectedServer?.id;
    final response = await _voiceRosterRequest();
    // The loads are the server's that was asked, and land on whichever is
    // selected now: after a switch mid-request, the new server's region
    // picker would show the old one's numbers.
    if (!response.success || asked == null) return response;
    if (state.selectedServer?.id != asked) return response;

    final data = response.data;
    if (data is! Map) return response;
    final regions = data['regions'];
    if (regions is! List) return response;

    emit(
      state.copyWith(
        regionLoad: {
          for (final row in regions)
            if (row is Map<String, dynamic>)
              if (RegionLoad.fromJson(row) case final load
                  when load.nodeId.isNotEmpty)
                load.nodeId: load,
        },
      ),
    );
    return response;
  }

  Future<APIResponse> _voiceRosterRequest() => _callWithAutoRefresh(
    (token) => _repository.voiceRoster(
      state.selectedServer!.supabaseUrl,
      bearerToken: token,
    ),
  );
}
