part of 'dm_cubit.dart';

/// Over the cubit-part budget and one job: sending a DM, from seal to post,
/// failure and retry; reading its attachments back is the last few lines.
///
/// Sending a DM (seal → upload attachments → post) and fetching attachment
/// bytes back for rendering.
mixin _DmSendMixin on Cubit<DmState> {
  Server? get _server;
  DmsApi get _dms;
  AttachmentsApi get _attachments;
  SavedConversation get _saved;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  Future<ServerIdentity> _vaultIdentityFor(Server server);

  /// Implemented by the conversations mixin.
  Future<void> refreshConversations();
  Future<void> refreshOpenLinkState();

  /// Implemented by the history mixin: what a retry reads first, in case the
  /// server stored the message after all, and the way out of a history window
  /// a send takes.
  Future<void> _fetchAfterLatest();
  Future<void> returnToPresent();

  /// The server these DMs are set up for, to tell a send that outlived it.
  String? get _readyServerId;

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
    Future<PendingLinkPreview?>? preview,
    String? replyToId,
  }) async =>
      await _sendAndSettle(
        text,
        attachments: attachments,
        preview: preview,
        replyToId: replyToId,
      ) ==
      _DmSendOutcome.refusedBack;

  /// [sendDm], or a retry of [earlier], with its files settled once it is
  /// over.
  Future<_DmSendOutcome> _sendAndSettle(
    String text, {
    List<PendingAttachment> attachments = const [],
    Future<PendingLinkPreview?>? preview,
    String? replyToId,
    OutboxEntry? earlier,
  }) async {
    final outcome = await _sendDm(
      text,
      attachments: attachments,
      preview: preview,
      replyToId: replyToId,
      earlier: earlier,
    );
    _outbox.settle(attachments, refused: outcome == _DmSendOutcome.refusedBack);
    return outcome;
  }

  /// Whether a message can go to the open conversation now.
  bool get _sendable {
    final peerId = state.openPeerId;
    return peerId != null &&
        _server?.user != null &&
        _dmKeys[peerId] != null &&
        state.chatStatus == DmChatStatus.ready;
  }

  /// [sendDm] itself; the wrapper settles the files once it is over.
  Future<_DmSendOutcome> _sendDm(
    String text, {
    List<PendingAttachment> attachments = const [],
    Future<PendingLinkPreview?>? preview,
    String? replyToId,
    OutboxEntry? earlier,
  }) async {
    if (!_sendable) return _DmSendOutcome.notSent;
    final peerId = state.openPeerId!;
    // Resolved against rows already decrypted and verified. A reference this
    // client cannot see is one it has no business asserting.
    final replyId = replyToId == null
        ? null
        : state.messages.where((m) => m.id == replyToId).firstOrNull?.id;
    final server = _server!;
    final user = server.user!;
    final key = _dmKeys[peerId]!;
    // Bound now: the send goes on if the reader walks away, even to another
    // server, and these follow the server this cubit is on.
    final dmsApi = _dms;
    final attachmentsApi = _attachments;
    final peerName = state.openPeerName;
    final serverId = _readyServerId;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return _DmSendOutcome.notSent;
    // Where the conversation stood when this message was first sent, for
    // telling it apart from an earlier one should its answer be lost.
    final storedAfter =
        earlier?.storedAfter ?? ChatMessageOps.latestId(state.messages);
    // Each attempt that reached the server and heard nothing back.
    final signatures = {...?earlier?.signatures};
    // What an earlier attempt already uploaded, named again rather than
    // uploaded twice.
    var uploadedFiles = earlier?.uploaded;

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
    // Kept in the outbox while it goes, so coming back finds it with its bar
    // (see the channel's send).
    emit(state.copyWith(messages: [...state.messages, pending]));
    _outbox.sending(peerId, pending);
    bool open() => state.openPeerId == peerId;

    // How a failure here is held for a retry.
    OutboxEntry heldAs(ChatMessage row) => OutboxEntry(
      destination: peerId,
      row: row,
      attachments: attachments,
      preview: preview,
      signatures: signatures,
      storedAfter: storedAfter,
      uploaded: uploadedFiles,
    );
    _DmSendOutcome fail({required String? errorCode, required String error}) =>
        _failSend(
          pending: pending,
          peerId: peerId,
          peerName: peerName,
          serverId: serverId,
          heldAs: heldAs,
          errorCode: errorCode,
          error: error,
        );

    try {
      final scope = DmCubit.conversationContext(
        user.id,
        peerId,
      ).replaceAll(':', '_');
      Future<APIResponse> uploadOne(
        PendingAttachment file, {
        TransferProgress? onProgress,
      }) => attachmentsApi.uploadStaged(
        file,
        scopePrefix: scope,
        onProgress: onProgress,
      );
      final again = uploadedFiles;
      final uploaded = again != null
          ? again.attachments
          : await ChatAttachmentUploader.uploadAll(
              pending: attachments,
              uploadOne: uploadOne,
              origin: attachmentsApi.origin,
              onProgress: (progress) {
                _outbox.progress(pendingId, progress);
                if (!open()) return;
                emit(
                  state.copyWith(
                    messages: ChatMessageOps.setUploadProgress(
                      state.messages,
                      pendingId,
                      progress,
                    ),
                  ),
                );
              },
            );
      final sentPreview = again != null
          ? again.preview
          : await ChatAttachmentUploader.uploadPreview(
              preview: preview,
              uploadOne: uploadOne,
              origin: attachmentsApi.origin,
            );
      uploadedFiles = UploadedFiles(
        attachments: uploaded,
        preview: sentPreview,
      );

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

      // Noted before it goes: an answer that never comes may still mean the
      // message was stored.
      signatures.add(envelope.signature);
      final response = await dmsApi.sendDm(
        recipientId: peerId,
        envelope: envelope.toJson(),
        attachmentPaths: uploadedFiles.paths,
      );

      if (!response.success) {
        // Refused: nothing will ever name these files. Not when an attempt
        // before this one went unanswered, which may have stored them.
        if (!Outbox.canRetry(response.errorCode) &&
            (earlier?.signatures.isEmpty ?? true)) {
          unawaited(attachmentsApi.deleteAttachments(uploadedFiles.paths));
        }
        final outcome = fail(
          errorCode: response.errorCode,
          error:
              DmRefusal.describe(
                response.errorCode,
                peerName: peerName ?? 'They',
              ) ??
              UploadedFiles.refusal(response.errorCode) ??
              response.error ??
              'Failed to send message',
        );
        // A refusal about the request says where things stand now.
        if (open()) unawaited(refreshOpenLinkState());
        return outcome;
      }

      final data = response.data as Map<String, dynamic>;
      final acked = ChatMessage(
        id: '${data['id']}',
        authorId: user.id,
        authorName: user.displayName,
        text: trimmed,
        attachments: uploaded,
        preview: sentPreview,
        replyToId: replyId,
        sentAt: DateTime.parse(data['created_at'] as String),
        isMine: true,
      );
      unawaited(refreshConversations());
      // Away, there is nothing to swap: the next open's page has it.
      if (!open()) return _DmSendOutcome.sent;
      // Sent from a stretch of history: added to its end, paging on from
      // there skipped everything between it and the live end. The live end
      // is where it is, so the conversation goes there instead.
      if (state.hasNewerHistory) {
        _removePending(pendingId);
        unawaited(returnToPresent());
        return _DmSendOutcome.sent;
      }
      emit(
        state.copyWith(
          messages: ChatMessageOps.replacePending(
            state.messages,
            pendingId: pendingId,
            acked: acked,
          ),
        ),
      );
      // Back, but with the page still on its way (see the channel's send).
      if (state.chatStatus == DmChatStatus.loading) {
        _outbox.landed(peerId, acked);
      }
      _saved.noteSent();
      // A first message may have become a request, and a reply to one is its
      // acceptance. Anything later in an open conversation changes nothing.
      if (state.openLinkState != DmLinkState.open ||
          state.messages.length <= 1) {
        unawaited(refreshOpenLinkState());
      }
      return _DmSendOutcome.sent;
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[DM] attachment upload failed: $e');
      return fail(errorCode: e.errorCode, error: 'Failed to upload attachment');
    } catch (e) {
      HelperMethods.printDebug('[DM] send failed: $e');
      return fail(errorCode: null, error: 'Failed to send message');
    } finally {
      _outbox.finished(pendingId);
    }
  }

  /// What happens to a pending row when the send did not land — see the
  /// channel mixin's copy for the reasoning, which is the same on all three
  /// surfaces. A refusal takes the row away and says why; a connection that
  /// dropped keeps it and holds what a retry would need.
  ///
  /// A refusal seen with the conversation still open is
  /// [_DmSendOutcome.refusedBack], which is when the words go back to the
  /// composer.
  ///
  /// A send that outlived its server — the reader moved to another while it
  /// was on its way — is not held: the outbox was emptied with that server's
  /// DMs, and nothing would ever draw the row again. It is said instead.
  _DmSendOutcome _failSend({
    required ChatMessage pending,
    required String peerId,
    required String? peerName,
    required String? serverId,
    required OutboxEntry Function(ChatMessage row) heldAs,
    required String? errorCode,
    required String error,
  }) {
    if (_readyServerId != serverId) {
      emit(
        state.copyWith(
          notice: Notice.error(
            'Your message to ${peerName ?? 'them'} was not sent.',
          ),
        ),
      );
      return _DmSendOutcome.refused;
    }
    final open = state.openPeerId == peerId;
    if (!Outbox.canRetry(errorCode)) {
      // Said wherever the reader is: the only news of a message that will
      // not arrive.
      if (open) _removePending(pending.id);
      emit(state.copyWith(notice: Notice.error(error)));
      return open ? _DmSendOutcome.refusedBack : _DmSendOutcome.refused;
    }
    _outbox.hold(heldAs(pending.copyWith(sendFailed: true)));
    if (open) {
      emit(
        state.copyWith(
          messages: ChatMessageOps.markFailed(state.messages, pending.id),
        ),
      );
    }
    return _DmSendOutcome.held;
  }

  /// Try one held send again — what tapping a "Not sent" row does.
  ///
  /// An attempt that reached the server and heard nothing back may have been
  /// stored, so the newest rows are read first: one of them being this
  /// message retires the row instead (`Outbox.retireStored`). Sent again
  /// unread, it reached them twice.
  ///
  /// A conversation that cannot take a message just now keeps the row and
  /// says so. Taken out first, the send gave up without a word and the
  /// message was gone.
  Future<void> retrySend(String pendingId) async {
    final held = _outbox.held(pendingId);
    if (held == null) return;
    if (!_sendable || state.openPeerId != held.destination) {
      emit(
        state.copyWith(
          notice: Notice.error(
            "This conversation can't take messages right now. Your message "
            'is kept.',
          ),
        ),
      );
      return;
    }
    if (held.signatures.isNotEmpty) {
      await _fetchAfterLatest();
      if (!_outbox.holds(pendingId)) return;
    }
    final entry = _outbox.take(pendingId);
    if (entry == null) return;
    emit(
      state.copyWith(
        messages: ChatMessageOps.removePending(state.messages, pendingId),
      ),
    );
    await _sendAndSettle(
      entry.text,
      attachments: entry.attachments,
      preview: entry.preview,
      replyToId: entry.row.replyToId,
      earlier: entry,
    );
  }

  /// Throw a held send away unsent — Delete on a "Not sent" row. Nobody else
  /// ever had it, so it goes from this device only, with its staged files.
  void discardSend(String pendingId) {
    if (!_outbox.holds(pendingId)) return;
    _outbox.drop(pendingId);
    _removePending(pendingId);
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
        origin: _attachments.origin,
        download: () => _attachments.downloadAttachment(
          path: attachment.storagePath,
          keyB64: attachment.keyB64,
          nonceB64: attachment.nonceB64,
          sha256B64: attachment.sha256B64,
          chunkSize: attachment.chunkSize,
          size: attachment.size,
        ),
      );

  /// Fetch an attachment into [sink] as it is opened, for saving it.
  Future<APIResponse> saveAttachment(
    Attachment attachment,
    BlobSink sink, {
    TransferProgress? onProgress,
  }) => _attachments.saveAttachment(
    attachment: attachment,
    sink: sink,
    onProgress: onProgress,
  );

  /// An attachment read as it plays, for a video.
  BlobReader? readAttachment(Attachment attachment) =>
      _attachments.readerFor(attachment);

  /// What the message list draws, saves and plays attachments with.
  AttachmentLoader get attachmentLoader => AttachmentLoader(
    origin: _attachments.origin,
    load: loadAttachment,
    save: saveAttachment,
    read: readAttachment,
  );
}

/// How a DM send ended — more than [DmCubit.sendDm]'s bool, for the quick
/// send, which has no row of its own to show a held message on.
enum _DmSendOutcome {
  /// The server stored it.
  sent,

  /// The connection failed; the row says "Not sent" and the outbox holds it.
  held,

  /// The server refused it with the conversation still open: the words go
  /// back to the composer.
  refusedBack,

  /// Refused, or lost with the server it was for, with nobody looking.
  refused,

  /// Never started: nothing to send, or the conversation cannot take it.
  notSent,
}
