part of 'server_cubit.dart';

/// Channel messages and channel keys (E2E messaging). Attachments and DMs
/// are their own parts.
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

  /// Publish the local user's X25519 chat public key (idempotent).
  Future<APIResponse> publishChatKey(String chatPublicKey) =>
      _callWithAutoRefresh(
        (token) => _repository.publishChatKey(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          userId: _userId,
          chatPublicKey: chatPublicKey,
          bearerToken: token,
        ),
      );

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

  /// The same for one server DM.
  Future<APIResponse> getDmMessage({required int messageId}) =>
      _callWithAutoRefresh(
        (token) => _repository.getDm(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          userId: _userId,
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

  /// Fetch my sealed channel keys + current version + healing set.
  Future<APIResponse> getChannelKey(String channelId, {String? serverId}) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _repository.getChannelKey(
        target.server.supabaseUrl,
        channelId: channelId,
        bearerToken: token,
      ),
    );
  }

  /// List key-distribution work available to the local user.
  Future<APIResponse> sweepChannelKeys() => _callWithAutoRefresh(
    (token) => _repository.sweepChannelKeys(
      state.selectedServer!.supabaseUrl,
      bearerToken: token,
    ),
  );

  /// Store sealed keyring entries for a key version — a new one when [mint],
  /// with the [link] that opens the version before it.
  Future<APIResponse> postChannelKeys({
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
    required bool mint,
    ({String ciphertext, String nonce})? link,
  }) => _callWithAutoRefresh(
    (token) => _repository.postChannelKeys(
      state.selectedServer!.supabaseUrl,
      channelId: channelId,
      keyVersion: keyVersion,
      entries: entries,
      mint: mint,
      link: link,
      bearerToken: token,
    ),
  );

  /// Drop our own keyring rows the channel's links already cover.
  Future<APIResponse> pruneChannelKeys(String channelId, List<int> versions) =>
      _callWithAutoRefresh(
        (token) => _repository.pruneChannelKeys(
          state.selectedServer!.supabaseUrl,
          anonKey: _anonKey,
          bearerToken: token,
          channelId: channelId,
          versions: versions,
        ),
      );
}
