part of 'central_dm_cubit.dart';

/// Sending a central DM, plus the daily quota it spends. Attachments count
/// against the same quota, so the meter is refreshed from every send.
mixin _CentralDmSendMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  String? get _myUserId;
  Future<ServerIdentity> _signingIdentity();

  /// Implemented by the conversations mixin.
  Future<void> refreshConversations();

  int _pendingCounter = 0;

  Future<void> refreshQuota() async {
    final response = await _repo.getQuota();
    if (isClosed || !response.success) return;
    final data = response.data as Map<String, dynamic>;
    emit(
      state.copyWith(
        quota: data['quota'] as int?,
        remaining: data['remaining'] as int?,
      ),
    );
  }

  Future<void> sendDm(
    String text, {
    List<PendingAttachment> attachments = const [],
  }) async {
    final peerId = state.openPeerId;
    final myId = _myUserId;
    if (peerId == null ||
        myId == null ||
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
            authorId: myId,
            authorName: state.myHandle ?? 'me',
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
            _repo.uploadAttachment(scopePrefix: myId, data: bytes),
      );
      if (state.openPeerId != peerId) return;

      final identity = await _signingIdentity();
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(text: trimmed, attachments: uploaded).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: _CentralDmHistoryMixin._context(myId, peerId),
        keyVersion: 1,
      );

      final response = await _repo.sendDm(
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
              authorId: myId,
              authorName: state.myHandle ?? 'me',
              text: trimmed,
              attachments: uploaded,
              sentAt: DateTime.parse(data['created_at'] as String),
              isMine: true,
            ),
          ),
          quota: data['quota'] as int?,
          remaining: data['remaining'] as int?,
        ),
      );
      unawaited(refreshConversations());
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[CentralDM] attachment upload failed: $e');
      if (state.openPeerId == peerId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to upload attachment');
      }
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] send failed: $e');
      if (state.openPeerId == peerId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to send message');
      }
    }
  }

  void _reportSendFailure(APIResponse response) {
    if (response.errorCode == 'quota_exceeded') {
      emit(state.copyWith(remaining: 0));
      HelperMethods.showError(
        error:
            'Daily central DM limit reached — continue on a shared '
            'server, or try again tomorrow.',
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
        download: () => _repo.downloadAttachment(
          path: attachment.storagePath,
          keyB64: attachment.keyB64,
          nonceB64: attachment.nonceB64,
        ),
      );
}
