part of 'server_cubit.dart';

/// The server's side of a call: the LiveKit token to join one, who is in
/// which channel, and moving or removing somebody.
mixin _ServerVoiceApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

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
}
