part of 'dm_cubit.dart';

/// Sending a DM (seal → upload attachments → post) and fetching attachment
/// bytes back for rendering.
mixin _DmSendMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  SavedConversation get _saved;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  Future<ServerIdentity> _vaultIdentityFor(Server server);

  /// Implemented by the conversations mixin.
  Future<void> refreshConversations();
  Future<void> refreshOpenLinkState();

  /// Sends that did not get out. On the class rather than here because the
  /// history mixin restores from it too (CODE_STYLE §5).
  Outbox get _outbox;

  int _pendingCounter = 0;

  /// [replyToId] names the message being answered. Sealed into the body like
  /// the text, so the two people in the conversation are the only ones who
  /// know which message it was. Nothing rings here: a DM already wakes its
  /// recipient, so there is no mentions array to add anybody to.
  ///
  /// Completes with true when the server refused the message and its row was
  /// taken away: the composer was emptied by the same press, so without being
  /// told it would lose the words for good (`ChatComposer.onSend`).
  Future<bool> sendDm(
    String text, {
    List<PendingAttachment> attachments = const [],
    PendingLinkPreview? preview,
    String? replyToId,
  }) async {
    final peerId = state.openPeerId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    if (peerId == null ||
        server == null ||
        user == null ||
        state.chatStatus != DmChatStatus.ready) {
      return false;
    }
    final key = _dmKeys[peerId];
    if (key == null) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return false;

    // Resolved against rows already decrypted and verified. A reference this
    // client cannot see is one it has no business asserting.
    final replyId = replyToId == null
        ? null
        : state.messages.where((m) => m.id == replyToId).firstOrNull?.id;

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
      replyToId: replyId,
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
      if (state.openPeerId != peerId) return false;

      final identity = await _vaultIdentityFor(server);
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(
          text: trimmed,
          attachments: uploaded,
          preview: sentPreview,
          replyToId: replyId,
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
      if (state.openPeerId != peerId) return false;

      if (!response.success) {
        final refused = _failSend(
          pending: pending,
          peerId: peerId,
          attachments: attachments,
          errorCode: response.errorCode,
          error:
              DmRefusal.describe(
                response.errorCode,
                peerName: state.openPeerName ?? 'They',
              ) ??
              response.error ??
              'Failed to send message',
        );
        // A refusal about the request says where things stand now.
        unawaited(refreshOpenLinkState());
        return refused;
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
              replyToId: replyId,
              sentAt: DateTime.parse(data['created_at'] as String),
              isMine: true,
            ),
          ),
        ),
      );
      _saved.noteSent();
      unawaited(refreshConversations());
      // A first message may have become a request, and a reply to one is its
      // acceptance. Anything later in an open conversation changes nothing.
      if (state.openLinkState != DmLinkState.open ||
          state.messages.length <= 1) {
        unawaited(refreshOpenLinkState());
      }
      return false;
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[DM] attachment upload failed: $e');
      return _failSend(
        pending: pending,
        peerId: peerId,
        attachments: attachments,
        errorCode: e.errorCode,
        error: 'Failed to upload attachment',
      );
    } catch (e) {
      HelperMethods.printDebug('[DM] send failed: $e');
      return _failSend(
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
  ///
  /// Returns whether it was a refusal seen with the conversation still open,
  /// which is when the words go back to the composer.
  bool _failSend({
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
      return open;
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
    return false;
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
    await sendDm(
      entry.text,
      attachments: entry.attachments,
      replyToId: entry.row.replyToId,
    );
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
