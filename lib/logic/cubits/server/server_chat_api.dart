part of 'server_cubit.dart';

/// Channel messages (E2E messaging). Attachments are their own part; the
/// channel keys are `ChannelKeysApi`.
///
/// Chat API wrappers. Thin pass-throughs to the repository —
/// all crypto happens in ChannelChatCubit/CryptoRepository; these only add
/// token auto-refresh and server resolution.
mixin _ServerChatApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  /// See [_ServerApiMixin] — what a direct PostgREST call needs alongside the
  /// bearer token.
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

  /// Store one E2E message envelope for [channelId].
  Future<APIResponse> sendChatMessage({
    required String channelId,
    required Map<String, dynamic> envelope,
    List<String> mentions = const [],
    bool mentionsAll = false,
    String? toBot,
    Map<String, dynamic>? poll,
    String? serverId,
  }) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _repository.sendMessage(
        target.server.supabaseUrl,
        anonKey: target.anonKey,
        channelId: channelId,
        envelope: envelope,
        mentions: mentions,
        mentionsAll: mentionsAll,
        toBot: toBot,
        poll: poll,
        bearerToken: token,
      ),
    );
  }

  /// Press something on a bot's panel.
  Future<APIResponse> sendPanelAction({
    required String channelId,
    required Map<String, dynamic> envelope,
    required String toBot,
    required int replyTo,
    required String actionId,
    String? actionValue,
  }) => _callWithAutoRefresh(
    (token) => _repository.sendPanelAction(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      channelId: channelId,
      envelope: envelope,
      toBot: toBot,
      replyTo: replyTo,
      actionId: actionId,
      actionValue: actionValue,
      bearerToken: token,
    ),
  );

  /// Replace one channel message's envelope (sender only).
  Future<APIResponse> editChatMessage({
    required String channelId,
    required int messageId,
    required Map<String, dynamic> envelope,
  }) => _callWithAutoRefresh(
    (token) => _repository.editMessage(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      messageId: messageId,
      envelope: envelope,
      bearerToken: token,
    ),
  );

  /// Hard-delete one channel message (sender, or a moderator) on [serverId],
  /// or the selected server — a report is acted on from its server's page.
  Future<APIResponse> deleteChatMessage({
    required String channelId,
    required int messageId,
    String? serverId,
  }) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _repository.deleteMessage(
        target.server.supabaseUrl,
        anonKey: target.anonKey,
        messageId: messageId,
        bearerToken: token,
      ),
    );
  }

  /// Page through a channel's message envelopes.
  Future<APIResponse> listChatMessages({
    required String channelId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) => _callWithAutoRefresh(
    (token) => _repository.listMessages(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      userId: _userId,
      channelId: channelId,
      beforeId: beforeId,
      afterId: afterId,
      limit: limit,
      bearerToken: token,
    ),
  );

  /// Re-read one channel message after a change doorbell named it. Answers
  /// `{message: …}`, or `{message: null}` when the row has been deleted.
  Future<APIResponse> getChatMessage({
    required String channelId,
    required int messageId,
  }) => _callWithAutoRefresh(
    (token) => _repository.getMessage(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      userId: _userId,
      channelId: channelId,
      messageId: messageId,
      bearerToken: token,
    ),
  );

  /// Toggle the caller's [emoji] reaction on a message ([scope] is `channel`
  /// or `dm`, which picks the table; who may react is a policy).
  Future<APIResponse> toggleReaction({
    required String scope,
    required int messageId,
    required String emoji,
  }) => _callWithAutoRefresh(
    (token) => _repository.toggleReaction(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      userId: _userId,
      scope: scope,
      messageId: messageId,
      emoji: emoji,
      bearerToken: token,
    ),
  );

  /// Aggregated reactions for a set of loaded messages.
  Future<APIResponse> listReactions({
    required String scope,
    required List<int> messageIds,
  }) => _callWithAutoRefresh(
    (token) => _repository.listReactions(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      userId: _userId,
      scope: scope,
      messageIds: messageIds,
      bearerToken: token,
    ),
  );
}
