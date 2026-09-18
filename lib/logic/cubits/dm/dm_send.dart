part of 'dm_cubit.dart';

/// Sending a DM (seal → upload attachments → post) and fetching attachment
/// bytes back for rendering.
mixin _DmSendMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  Future<ServerIdentity> _vaultIdentityFor(Server server);

  /// Implemented by the conversations mixin.
  Future<void> refreshConversations();

  /// Sends that did not get out. On the class rather than here because the
  /// history mixin restores from it too (CODE_STYLE §5).
  Outbox get _outbox;

  int _pendingCounter = 0;

  Future<void> sendDm(
    String text, {
    List<PendingAttachment> attachments = const [],
    PendingLinkPreview? preview,
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
    // Held in a local as well as emitted: if this send fails it becomes the row
    // the outbox keeps, and by then the reader may have left the conversation
    // — so it cannot be read back out of state.
    final pending = ChatMessage(
      id: pendingId,
      authorId: user.id,
      authorName: user.displayName,
      text: trimmed,
      sentAt: DateTime.now(),
      isMine: true,
      isPending: true,
    );
    emit(state.copyWith(messages: [...state.messages, pending]));

    try {
      final scope = DmCubit.conversationContext(
        user.id,
        peerId,
      ).replaceAll(':', '_');
      Future<APIResponse> uploadOne(Uint8List bytes) =>
          _serverCubit.uploadAttachment(scopePrefix: scope, data: bytes);
      final uploaded = await ChatAttachmentUploader.uploadAll(
        pending: attachments,
        uploadOne: uploadOne,
      );
      final sentPreview = await ChatAttachmentUploader.uploadPreview(
        pending: preview,
        uploadOne: uploadOne,
      );
      if (state.openPeerId != peerId) return;

      final identity = await _vaultIdentityFor(server);
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(
          text: trimmed,
          attachments: uploaded,
          preview: sentPreview,
        ).encode(),
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
        _failSend(
          pending: pending,
          peerId: peerId,
          attachments: attachments,
          errorCode: response.errorCode,
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
              preview: sentPreview,
              sentAt: DateTime.parse(data['created_at'] as String),
              isMine: true,
            ),
          ),
        ),
      );
      unawaited(refreshConversations());
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[DM] attachment upload failed: $e');
      _failSend(
        pending: pending,
        peerId: peerId,
        attachments: attachments,
        errorCode: e.errorCode,
        error: 'Failed to upload attachment',
      );
    } catch (e) {
      HelperMethods.printDebug('[DM] send failed: $e');
      _failSend(
        pending: pending,
        peerId: peerId,
        attachments: attachments,
        errorCode: null,
        error: 'Failed to send message',
      );
    }
  }

  /// What happens to a pending row when the send did not land — see the
  /// channel mixin's copy for the reasoning, which is the same on all three
  /// surfaces. A refusal takes the row away and says why; a connection that
  /// dropped keeps it and holds what a retry would need.
  void _failSend({
    required ChatMessage pending,
    required String peerId,
    required List<PendingAttachment> attachments,
    required String? errorCode,
    required String error,
  }) {
    final open = state.openPeerId == peerId;
    if (!Outbox.canRetry(errorCode)) {
      if (open) {
        _removePending(pending.id);
        HelperMethods.showError(error: error);
      }
      return;
    }
    _outbox.hold(
      OutboxEntry(
        destination: peerId,
        row: pending.copyWith(sendFailed: true),
        attachments: attachments,
      ),
    );
    if (open) {
      emit(
        state.copyWith(
          messages: ChatMessageOps.markFailed(state.messages, pending.id),
        ),
      );
    }
  }

  /// Try one held send again — what tapping a "Not sent" row does.
  Future<void> retrySend(String pendingId) async {
    final entry = _outbox.take(pendingId);
    if (entry == null) return;
    emit(
      state.copyWith(
        messages: ChatMessageOps.removePending(state.messages, pendingId),
      ),
    );
    await sendDm(entry.text, attachments: entry.attachments);
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
