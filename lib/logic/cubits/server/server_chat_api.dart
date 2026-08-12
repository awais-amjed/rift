part of 'server_cubit.dart';

/// Chat API wrappers (E2E messaging). Thin pass-throughs to the repository —
/// all crypto happens in ChannelChatCubit/CryptoRepository; these only add
/// token auto-refresh and server resolution.
mixin _ServerChatApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  AttachmentRepository get _attachments;

  /// See [_ServerApiMixin] — what a direct PostgREST call needs alongside the
  /// bearer token.
  String get _anonKey;
  String get _userId;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  static const String _attachmentsBucket = 'chat-attachments';

  /// Encrypt + upload an attachment blob to the selected server, scoped under
  /// [scopePrefix] (channel id / DM context). On success `data` is
  /// `({String path, String keyB64, String nonceB64})`.
  Future<APIResponse> uploadAttachment({
    required String scopePrefix,
    required Uint8List data,
  }) {
    final server = state.selectedServer;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) {
      return Future.value(APIResponse.error('No server selected'));
    }
    return _callWithAutoRefresh(
      (token) => _attachments.uploadEncrypted(
        baseUrl: server.supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
        bucket: _attachmentsBucket,
        scopePrefix: scopePrefix,
        data: data,
      ),
    );
  }

  /// Remove attachment blobs from the selected server.
  ///
  /// Called when a message carrying them is deleted: the client has just
  /// decrypted that message, so it is the only party that knows which blobs
  /// belong to it. Best-effort — see [AttachmentRepository.deleteObjects].
  Future<APIResponse> deleteAttachments(List<String> paths) {
    final server = state.selectedServer;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) {
      return Future.value(APIResponse.error('No server selected'));
    }
    return _callWithAutoRefresh(
      (token) => _attachments.deleteObjects(
        baseUrl: server.supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
        bucket: _attachmentsBucket,
        paths: paths,
      ),
    );
  }

  /// Apply this server's retention settings and clear out the attachment blobs
  /// whose messages are gone. Safe for any member to call — it removes only
  /// unreferenced objects.
  Future<APIResponse> sweepAttachments() {
    final server = state.selectedServer;
    if (server == null) {
      return Future.value(APIResponse.error('No server selected'));
    }
    return _callWithAutoRefresh(
      (token) =>
          _repository.sweepAttachments(server.supabaseUrl, bearerToken: token),
    );
  }

  /// Download + decrypt an attachment blob from the selected server. On success
  /// `data` is the decrypted `Uint8List`.
  Future<APIResponse> downloadAttachment({
    required String path,
    required String keyB64,
    required String nonceB64,
  }) {
    final server = state.selectedServer;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) {
      return Future.value(APIResponse.error('No server selected'));
    }
    return _callWithAutoRefresh(
      (token) => _attachments.downloadDecrypted(
        baseUrl: server.supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
        bucket: _attachmentsBucket,
        path: path,
        keyB64: keyB64,
        nonceB64: nonceB64,
      ),
    );
  }

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
  }) => _callWithAutoRefresh(
    (token) => _repository.sendMessage(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      channelId: channelId,
      envelope: envelope,
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

  /// Hard-delete one channel message (sender, or a moderator).
  Future<APIResponse> deleteChatMessage({
    required String channelId,
    required int messageId,
  }) => _callWithAutoRefresh(
    (token) => _repository.deleteMessage(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      messageId: messageId,
      bearerToken: token,
    ),
  );

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
  Future<APIResponse> getChannelKey(String channelId) => _callWithAutoRefresh(
    (token) => _repository.getChannelKey(
      state.selectedServer!.supabaseUrl,
      channelId: channelId,
      bearerToken: token,
    ),
  );

  /// List key-distribution work available to the local user.
  Future<APIResponse> sweepChannelKeys() => _callWithAutoRefresh(
    (token) => _repository.sweepChannelKeys(
      state.selectedServer!.supabaseUrl,
      bearerToken: token,
    ),
  );

  /// Store one E2E DM envelope for [recipientId].
  Future<APIResponse> sendDm({
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) => _callWithAutoRefresh(
    (token) => _repository.sendDm(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      recipientId: recipientId,
      envelope: envelope,
      bearerToken: token,
    ),
  );

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

  /// List DM conversations for the local user.
  Future<APIResponse> listDmConversations() => _callWithAutoRefresh(
    (token) => _repository.listDmConversations(
      state.selectedServer!.supabaseUrl,
      anonKey: _anonKey,
      bearerToken: token,
    ),
  );

  /// Store sealed keyring entries for a key version.
  Future<APIResponse> postChannelKeys({
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
  }) => _callWithAutoRefresh(
    (token) => _repository.postChannelKeys(
      state.selectedServer!.supabaseUrl,
      channelId: channelId,
      keyVersion: keyVersion,
      entries: entries,
      bearerToken: token,
    ),
  );
}
