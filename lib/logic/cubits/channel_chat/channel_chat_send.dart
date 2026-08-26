part of 'channel_chat_cubit.dart';

/// Sending into a channel, and fetching attachment bytes back for rendering.
mixin _ChannelChatSendMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  ServerMembersCubit get _membersCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  int get _currentKeyVersion;
  void _ringDoorbell();

  int _pendingCounter = 0;

  /// Seal, sign, and send a message ([text] and/or [attachments]); shows an
  /// optimistic pending message until the server acknowledges. Attachments are
  /// encrypted + uploaded first; on any failure the pending message is removed
  /// and an error toast shown.
  Future<void> sendMessage(
    String text, {
    List<PendingAttachment> attachments = const [],
  }) async {
    final channelId = state.channelId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    final key = _keys[_currentKeyVersion];
    if (channelId == null ||
        server == null ||
        user == null ||
        key == null ||
        state.status != ChannelChatStatus.ready) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;

    final pendingId = 'pending-${_pendingCounter++}';
    // Show the text immediately; attachments appear once uploaded.
    emit(
      state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            id: pendingId,
            authorId: user.id,
            authorName: user.displayName,
            text: trimmed,
            sentAt: DateTime.now(),
            isMine: true,
            isPending: true,
          ),
        ],
      ),
    );

    try {
      final uploaded = await ChatAttachmentUploader.uploadAll(
        pending: attachments,
        uploadOne: (bytes) =>
            _serverCubit.uploadAttachment(scopePrefix: channelId, data: bytes),
      );
      if (state.channelId != channelId) return;

      final host = Uri.parse(server.supabaseUrl).host;
      final identity = await _vaultCubit.getIdentityForHost(
        host,
        serverId: server.id,
        version: server.keyVersion,
      );
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(text: trimmed, attachments: uploaded).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: channelId,
        keyVersion: _currentKeyVersion,
      );

      // The one part of a message that travels in the clear. See
      // `ServerRepository.sendMessage` for what that costs and buys.
      // Empty while the roster is still loading, which costs the message its
      // pings rather than its delivery — the right way round. The alternative
      // is blocking a send on a fetch only needed to decide whose phone buzzes.
      final named = Mentions.resolve(
        trimmed,
        idsByUsername: Mentions.rosterOf(
          _membersCubit.state.members ?? const [],
        ),
        excludeUserId: user.id,
      );

      final response = await _serverCubit.sendChatMessage(
        channelId: channelId,
        envelope: envelope.toJson(),
        mentions: named.userIds,
        mentionsAll: named.all,
      );
      if (state.channelId != channelId) return;

      if (!response.success) {
        _removePending(pendingId);
        HelperMethods.showError(
          error: response.error ?? 'Failed to send message',
        );
        return;
      }

      final data = response.data as Map<String, dynamic>;
      emit(
        state.copyWith(
          messages: ChatMessageOps.replacePending(
            state.messages,
            pendingId: pendingId,
            acked: ChatMessage(
              id: '${data['id']}',
              authorId: user.id,
              authorName: user.displayName,
              text: trimmed,
              attachments: uploaded,
              sentAt: DateTime.parse(data['created_at'] as String),
              isMine: true,
            ),
          ),
        ),
      );
      _ringDoorbell();
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[Chat] attachment upload failed: $e');
      if (state.channelId == channelId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to upload attachment');
      }
    } catch (e) {
      HelperMethods.printDebug('[Chat] send failed: $e');
      if (state.channelId == channelId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to send message');
      }
    }
  }

  void _removePending(String pendingId) {
    emit(
      state.copyWith(
        messages: ChatMessageOps.removePending(state.messages, pendingId),
      ),
    );
  }

  /// Fetch + decrypt an attachment's bytes (cache-first) for rendering.
  Future<Uint8List?> loadAttachment(Attachment attachment) =>
      ChatAttachmentUploader.load(
        attachment: attachment,
        download: () => _serverCubit.downloadAttachment(
          path: attachment.storagePath,
          keyB64: attachment.keyB64,
          nonceB64: attachment.nonceB64,
        ),
      );
}
