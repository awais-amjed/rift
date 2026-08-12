part of 'dm_cubit.dart';

/// Sending a DM (seal → upload attachments → post) and fetching attachment
/// bytes back for rendering.
mixin _DmSendMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  Future<ServerIdentity> _vaultIdentityFor(Server server);
  void _ringPeerDoorbell();

  /// Implemented by the conversations mixin.
  Future<void> refreshConversations();

  int _pendingCounter = 0;

  /// Re-read how many DMs are left today.
  ///
  /// Unlike a channel's, this budget is shared by every conversation on the
  /// server, so it is refreshed when a conversation opens rather than being
  /// tied to one peer.
  Future<void> refreshQuota() async {
    final result = await _serverCubit.fetchChatQuota();
    if (isClosed || result == null) return;
    emit(state.copyWith(quota: ChatQuota.fromResult(result)));
  }

  Future<void> sendDm(
    String text, {
    List<PendingAttachment> attachments = const [],
  }) async {
    final peerId = state.openPeerId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    if (peerId == null ||
        server == null ||
        user == null ||
        state.chatStatus != DmChatStatus.ready) {
      return;
    }
    final key = _dmKeys[peerId];
    if (key == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;

    final pendingId = 'pending-${_pendingCounter++}';
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
      final scope = DmCubit.conversationContext(
        user.id,
        peerId,
      ).replaceAll(':', '_');
      final uploaded = await ChatAttachmentUploader.uploadAll(
        pending: attachments,
        uploadOne: (bytes) =>
            _serverCubit.uploadAttachment(scopePrefix: scope, data: bytes),
      );
      if (state.openPeerId != peerId) return;

      final identity = await _vaultIdentityFor(server);
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(text: trimmed, attachments: uploaded).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: DmCubit.conversationContext(user.id, peerId),
        keyVersion: 1,
      );

      final response = await _serverCubit.sendDm(
        recipientId: peerId,
        envelope: envelope.toJson(),
      );
      if (state.openPeerId != peerId) return;

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
      _ringPeerDoorbell();
      unawaited(refreshConversations());
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[DM] attachment upload failed: $e');
      if (state.openPeerId == peerId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to upload attachment');
      }
    } catch (e) {
      HelperMethods.printDebug('[DM] send failed: $e');
      if (state.openPeerId == peerId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to send message');
      }
    }
  }

  /// The quota wall gets its own sentence and pins the meter at zero. The
  /// wording points at a channel, because that is what a server DM's limit is
  /// there to push long conversations towards — the same nudge central makes
  /// towards a shared server.
  void _reportSendFailure(APIResponse response) {
    if (response.errorCode == ErrorCode.quotaExceeded) {
      emit(state.copyWith(quota: state.quota.spent));
      HelperMethods.showError(
        error:
            "You've hit this server's daily direct-message limit. "
            'Carry on in a channel, or try again tomorrow.',
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
