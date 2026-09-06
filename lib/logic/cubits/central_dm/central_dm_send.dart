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

  /// Implemented by the friends mixin.
  Future<void> loadFriends();

  /// Sends that did not get out. On the class rather than here because the
  /// history mixin restores from it too (CODE_STYLE §5).
  Outbox get _outbox;

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
    PendingLinkPreview? preview,
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
    // Held in a local as well as emitted: if this send fails it becomes the row
    // the outbox keeps, and by then the reader may have left the conversation
    // — so it cannot be read back out of state.
    final pending = ChatMessage(
      id: pendingId,
      authorId: myId,
      authorName: state.myHandle ?? 'me',
      text: trimmed,
      sentAt: DateTime.now(),
      isMine: true,
      isPending: true,
    );
    emit(state.copyWith(messages: [...state.messages, pending]));

    try {
      Future<APIResponse> uploadOne(Uint8List bytes) =>
          _repo.uploadAttachment(scopePrefix: myId, data: bytes);
      final uploaded = await ChatAttachmentUploader.uploadAll(
        pending: attachments,
        uploadOne: uploadOne,
      );
      final sentPreview = await ChatAttachmentUploader.uploadPreview(
        pending: preview,
        uploadOne: uploadOne,
      );
      if (state.openPeerId != peerId) return;

      final identity = await _signingIdentity();
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(
          text: trimmed,
          attachments: uploaded,
          preview: sentPreview,
        ).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: _CentralDmDecryptMixin._context(myId, peerId),
        keyVersion: 1,
      );

      final response = await _repo.sendDm(
        recipientId: peerId,
        envelope: envelope.toJson(),
      );
      if (state.openPeerId != peerId) return;

      if (!response.success) {
        // The quota and the friendship walls are refusals with something to
        // say, and [_reportSendFailure] is where they are said. It is reached
        // only for a response that actually came back — a send that never
        // arrived has no code, and nothing about the account to report.
        if (Outbox.canRetry(response.errorCode)) {
          _failSend(pending: pending, peerId: peerId, attachments: attachments);
        } else if (state.openPeerId == peerId) {
          _removePending(pendingId);
          _reportSendFailure(response);
        }
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
      // A send cannot move the relationship any more — being friends is what
      // made it possible — but it can *reveal* that this device was wrong
      // about it. The server always answers `friends`, so a disagreement here
      // means the local graph is stale, and re-reading it is cheaper than
      // waiting for something else to ask.
      if (FriendshipState.parse(data['state']) != state.stateFor(peerId)) {
        unawaited(loadFriends());
      }
      unawaited(refreshConversations());
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[CentralDM] attachment upload failed: $e');
      if (Outbox.canRetry(e.errorCode)) {
        _failSend(pending: pending, peerId: peerId, attachments: attachments);
      } else if (state.openPeerId == peerId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to upload attachment');
      }
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] send failed: $e');
      // No code to read, so no claim that a retry would help.
      if (state.openPeerId == peerId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to send message');
      }
    }
  }

  /// Keep a send the connection lost, and mark the row so it says so.
  ///
  /// Only ever called for a retryable failure — the refusals go through
  /// [_reportSendFailure], which has something specific to say and nothing to
  /// offer a retry for. Holds whether or not the conversation is still open,
  /// so walking away mid-failure does not lose the message
  /// (`Outbox.restoreInto` brings it back).
  void _failSend({
    required ChatMessage pending,
    required String peerId,
    required List<PendingAttachment> attachments,
  }) {
    _outbox.hold(
      OutboxEntry(
        destination: peerId,
        row: pending.copyWith(sendFailed: true),
        attachments: attachments,
      ),
    );
    if (state.openPeerId == peerId) {
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

  void _reportSendFailure(APIResponse response) {
    switch (response.errorCode) {
      case 'quota_exceeded':
        emit(state.copyWith(remaining: 0));
        HelperMethods.showError(
          error:
              'Daily central DM limit reached — continue on a shared '
              'server, or try again tomorrow.',
        );
      // The composer should not have existed. Reaching here means this
      // device's graph was stale — they unfriended or blocked while the
      // message was being typed — so re-read it and let the UI close itself.
      //
      // One sentence for every way of not being friends, because the server
      // gives one code for all of them on purpose: which of the two blocked
      // the other, or whether anybody did, is not the sender's to learn from
      // a bounce.
      case 'not_friends':
        unawaited(loadFriends());
        HelperMethods.showError(
          error: 'You can only message people you are friends with.',
        );
      default:
        HelperMethods.showError(
          error: response.error ?? 'Failed to send message',
        );
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
        download: () => _repo.downloadAttachment(
          path: attachment.storagePath,
          keyB64: attachment.keyB64,
          nonceB64: attachment.nonceB64,
        ),
      );
}
