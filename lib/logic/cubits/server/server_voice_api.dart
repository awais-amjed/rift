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
        : await _regionProbe.nearest(server.id, server.livekitNodes);

    return _callWithAutoRefresh(
      (token) => _repository.getChannelToken(
        state.selectedServer!.supabaseUrl,
        channelId,
        screenShare: screenShare,
        soundShare: soundShare,
        preferredNodeId: preferred,
        bearerToken: token,
      ),
    );
  }

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
}
