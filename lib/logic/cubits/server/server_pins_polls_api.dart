part of 'server_cubit.dart';

/// Pins and polls on the selected server. Thin pass-throughs — the chat cubits
/// hold the state, decrypt the pinned rows, and merge the tallies.
mixin _ServerPinsPollsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  String get _anonKey;
  String get _userId;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  // ── Pins ──────────────────────────────────────────────────

  /// Pin or unpin a message ([scope] is `channel` or `dm`).
  Future<APIResponse> setPinned({
    required String scope,
    required int messageId,
    required bool pinned,
  }) => _callWithAutoRefresh(
    (token) => _repository.setPinned(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      bearerToken: token,
      scope: scope,
      messageId: messageId,
      pinned: pinned,
    ),
  );

  /// A channel's pinned message rows, newest pin first.
  Future<APIResponse> listChannelPins({required String channelId}) =>
      _callWithAutoRefresh(
        (token) => _repository.listChannelPins(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          userId: _userId,
          bearerToken: token,
          channelId: channelId,
        ),
      );

  /// The pinned rows of the server DM with [peerId], newest pin first.
  Future<APIResponse> listDmPins({required String peerId}) =>
      _callWithAutoRefresh(
        (token) => _repository.listDmPins(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          userId: _userId,
          bearerToken: token,
          peerId: peerId,
        ),
      );

  // ── Polls ─────────────────────────────────────────────────

  /// Tallies for the polls among [messageIds].
  Future<APIResponse> pollTallies({required List<int> messageIds}) =>
      _callWithAutoRefresh(
        (token) => _repository.pollTallies(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          bearerToken: token,
          messageIds: messageIds,
        ),
      );

  /// Replace the caller's ballot on a poll; answers with the new tally.
  Future<APIResponse> votePoll({
    required int messageId,
    required List<int> options,
  }) => _callWithAutoRefresh(
    (token) => _repository.votePoll(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      bearerToken: token,
      messageId: messageId,
      options: options,
    ),
  );

  /// End a poll now (its author only).
  Future<APIResponse> closePoll({required int messageId}) =>
      _callWithAutoRefresh(
        (token) => _repository.closePoll(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          bearerToken: token,
          messageId: messageId,
        ),
      );
}
