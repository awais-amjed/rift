part of 'server_cubit.dart';

/// A server's own DMs: sealed envelopes between two members of it, stored on
/// that server like channel messages are.
mixin _ServerDmsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  /// See [_ServerApiMixin].
  String get _anonKey;
  String get _userId;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  String _noTarget(String? serverId);

  /// See [ServerCubit._chatTarget].
  ({Server server, String anonKey})? _chatTarget(String? serverId);

  /// Replace one server-DM envelope (sender only).
  Future<APIResponse> editDm({
    required int messageId,
    required Map<String, dynamic> envelope,
  }) => _callWithAutoRefresh(
    (token) => _repository.editDm(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      messageId: messageId,
      envelope: envelope,
      bearerToken: token,
    ),
  );

  /// Hard-delete one server DM (sender only).
  Future<APIResponse> deleteDm({required int messageId}) =>
      _callWithAutoRefresh(
        (token) => _repository.deleteDm(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          messageId: messageId,
          bearerToken: token,
        ),
      );

  /// Store one E2E DM envelope for [recipientId].
  Future<APIResponse> sendDm({
    required String recipientId,
    required Map<String, dynamic> envelope,
    String? serverId,
  }) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _repository.sendDm(
        target.server.supabaseUrl,
        anonKey: target.anonKey,
        recipientId: recipientId,
        envelope: envelope,
        bearerToken: token,
      ),
    );
  }

  /// Page through the DM conversation with [peerId].
  Future<APIResponse> listDms({
    required String peerId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) => _callWithAutoRefresh(
    (token) => _repository.listDms(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      userId: _userId,
      peerId: peerId,
      beforeId: beforeId,
      afterId: afterId,
      limit: limit,
      bearerToken: token,
    ),
  );

  /// One page of the local user's DM conversations, newest activity first.
  ///
  /// [before] is the cursor: the newest message id of the last row already
  /// held. Null asks for the top.
  Future<APIResponse> listDmConversations({int? before}) =>
      _callWithAutoRefresh(
        (token) => _repository.listDmConversations(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          bearerToken: token,
          before: before,
        ),
      );
}
