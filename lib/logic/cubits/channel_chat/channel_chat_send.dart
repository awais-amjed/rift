part of 'channel_chat_cubit.dart';

/// Sending into a channel, and fetching attachment bytes back for rendering.
mixin _ChannelChatSendMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  int get _currentKeyVersion;
  void _ringDoorbell();

  int _pendingCounter = 0;

  /// Re-read how many messages are left in [channelId] today.
  ///
  /// Called on open rather than after every send: sends decrement the local
  /// count, and the number that has to be right is the one an admin's change —
  /// or another device — would have moved while the channel was closed.
  Future<void> refreshQuota(String channelId) async {
    final result = await _serverCubit.fetchChatQuota(channelId: channelId);
    if (isClosed || result == null || state.channelId != channelId) return;
    emit(state.copyWith(quota: ChatQuota.fromResult(result)));
  }

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

      final response = await _serverCubit.sendChatMessage(
        channelId: channelId,
        envelope: envelope.toJson(),
      );
      if (state.channelId != channelId) return;

      if (!response.success) {
        _removePending(pendingId);
        _reportSendFailure(response);
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
          quota: state.quota.spendOne(),
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

  /// The quota wall gets its own sentence and pins the meter at zero — a
  /// generic "failed to send" would read as a network problem, and the meter
  /// may not have known it was the last message (another device spends the
  /// same budget).
  void _reportSendFailure(APIResponse response) {
    if (response.errorCode == ErrorCode.quotaExceeded) {
      emit(state.copyWith(quota: state.quota.spent));
      HelperMethods.showError(
        error:
            "You've hit this channel's daily message limit. "
            'It resets 24 hours after your earliest message today.',
      );
      return;
    }
    HelperMethods.showError(error: response.error ?? 'Failed to send message');
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
