part of 'central_dm_cubit.dart';

/// Over the cubit-part budget and one job: a send and the quota it spends,
/// which move together.
///
/// Sending a central DM, plus the daily quota it spends. Attachments count
/// against the same quota, so the meter is refreshed from every send.
mixin _CentralDmSendMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;
  SavedConversation get _saved;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  String? get _myUserId;
  Future<ServerIdentity> _signingIdentity();

  /// Implemented by the conversations mixin.
  Future<void> refreshConversations();

  /// Implemented by the friends mixin.
  Future<void> loadFriends();

  /// Implemented by the history mixin: what a retry reads first, in case
  /// central stored the message after all, and the way out of a history
  /// window a send takes.
  Future<void> _fetchAfterLatest();
  Future<void> returnToPresent();

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

  /// [replyToId] names the message being answered. Sealed into the body like
  /// the text, so the two people in the conversation are the only ones who
  /// know which message it was. Nothing rings here: a DM already wakes its
  /// recipient, so there is no mentions array to add anybody to.
  ///
  /// Completes with true when the server refused the message and its row was
  /// taken away, so the composer can give the words back
  /// (`ChatComposer.onSend`).
  Future<bool> sendDm(
    String text, {
    List<PendingAttachment> attachments = const [],
    Future<PendingLinkPreview?>? preview,
    String? replyToId,
  }) => _sendAndSettle(
    text,
    attachments: attachments,
    preview: preview,
    replyToId: replyToId,
  );

  /// [sendDm], or a retry of [earlier], with its files settled once it is
  /// over.
  Future<bool> _sendAndSettle(
    String text, {
    List<PendingAttachment> attachments = const [],
    Future<PendingLinkPreview?>? preview,
    String? replyToId,
    OutboxEntry? earlier,
  }) async {
    final refused = await _sendDm(
      text,
      attachments: attachments,
      preview: preview,
      replyToId: replyToId,
      earlier: earlier,
    );
    _outbox.settle(attachments, refused: refused);
    return refused;
  }

  /// Whether a message can go to the open conversation now.
  bool get _sendable {
    final peerId = state.openPeerId;
    return peerId != null &&
        _myUserId != null &&
        _dmKeys[peerId] != null &&
        state.chatStatus == DmChatStatus.ready;
  }

  /// [sendDm] itself; the wrapper settles the files once it is over.
  Future<bool> _sendDm(
    String text, {
    List<PendingAttachment> attachments = const [],
    Future<PendingLinkPreview?>? preview,
    String? replyToId,
    OutboxEntry? earlier,
  }) async {
    if (!_sendable) return false;
    final peerId = state.openPeerId!;
    final myId = _myUserId!;
    final key = _dmKeys[peerId]!;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return false;
    // Where the conversation stood when this message was first sent, for
    // telling it apart from an earlier one should its answer be lost.
    final storedAfter =
        earlier?.storedAfter ?? ChatMessageOps.latestId(state.messages);
    // Each attempt that reached central and heard nothing back.
    final signatures = {...?earlier?.signatures};
    // What an earlier attempt already uploaded, named again rather than
    // uploaded twice.
    var uploadedFiles = earlier?.uploaded;

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
      authorId: myId,
      authorName: state.myHandle ?? 'me',
      text: trimmed,
      sentAt: DateTime.now(),
      isMine: true,
      isPending: true,
      replyToId: replyId,
    );
    // Kept in the outbox while it goes, so coming back finds it with its bar
    // (see the channel's send). The send goes on if the reader walks away.
    emit(state.copyWith(messages: [...state.messages, pending]));
    _outbox.sending(peerId, pending);
    bool open() => state.openPeerId == peerId;

    // How a failure here is held for a retry.
    void hold() => _failSend(
      pending: pending,
      myId: myId,
      entry: OutboxEntry(
        destination: peerId,
        row: pending.copyWith(sendFailed: true),
        attachments: attachments,
        preview: preview,
        signatures: signatures,
        storedAfter: storedAfter,
        uploaded: uploadedFiles,
      ),
    );

    try {
      // Always encrypted and always in one request: the composer offers no
      // choice here, and central's files stop at 10 MB, under the size that
      // is sent a chunk at a time.
      Future<APIResponse> uploadOne(
        PendingAttachment file, {
        TransferProgress? onProgress,
      }) async => _repo.uploadAttachment(
        scopePrefix: myId,
        data: file.bytes ?? await file.source.readAsBytes(),
      );
      final again = uploadedFiles;
      final uploaded = again != null
          ? again.attachments
          : await ChatAttachmentUploader.uploadAll(
              pending: attachments,
              uploadOne: uploadOne,
              origin: AttachmentLoader.central,
              // One request a file, so the bar moves a file at a time.
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
              origin: AttachmentLoader.central,
            );
      uploadedFiles = UploadedFiles(
        attachments: uploaded,
        preview: sentPreview,
      );

      final identity = await _signingIdentity();
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(
          text: trimmed,
          attachments: uploaded,
          preview: sentPreview,
          replyToId: replyId,
        ).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: _CentralDmDecryptMixin._context(myId, peerId),
        keyVersion: 1,
      );

      // Noted before it goes: an answer that never comes may still mean the
      // message was stored.
      signatures.add(envelope.signature);
      final response = await _repo.sendDm(
        recipientId: peerId,
        envelope: envelope.toJson(),
      );

      if (!response.success) {
        // The quota and the friendship walls are refusals with something to
        // say, and [_reportSendFailure] is where they are said. It is reached
        // only for a response that actually came back — a send that never
        // arrived has no code, and nothing about the account to report.
        if (Outbox.canRetry(response.errorCode)) {
          hold();
          return false;
        }
        // Refused: nothing will ever name these files. Not when an attempt
        // before this one went unanswered, which may have stored them.
        if (earlier?.signatures.isEmpty ?? true) {
          unawaited(_repo.deleteAttachments(uploadedFiles.paths));
        }
        // Said wherever the reader is: the only news of a message that
        // will not arrive.
        if (open()) _removePending(pendingId);
        _reportSendFailure(response);
        return open();
      }

      final data = response.data as Map<String, dynamic>;
      final acked = ChatMessage(
        id: '${data['id']}',
        authorId: myId,
        authorName: state.myHandle ?? 'me',
        text: trimmed,
        attachments: uploaded,
        preview: sentPreview,
        replyToId: replyId,
        sentAt: DateTime.parse(data['created_at'] as String),
        isMine: true,
      );
      // Sent from a stretch of history: added to its end, paging on from
      // there skipped everything between it and the live end. The live end
      // is where it is, so the conversation goes there instead.
      if (open() && state.hasNewerHistory) {
        _removePending(pendingId);
        emit(
          state.copyWith(
            quota: data['quota'] as int?,
            remaining: data['remaining'] as int?,
          ),
        );
        unawaited(returnToPresent());
        unawaited(refreshConversations());
        return false;
      }
      final here = open();
      emit(
        state.copyWith(
          // Away, there is nothing to swap: the next open's page has it.
          messages: here
              ? ChatMessageOps.replacePending(
                  state.messages,
                  pendingId: pendingId,
                  acked: acked,
                )
              : null,
          quota: data['quota'] as int?,
          remaining: data['remaining'] as int?,
        ),
      );
      // Back, but with the page still on its way (see the channel's send).
      if (here && state.chatStatus == DmChatStatus.loading) {
        _outbox.landed(peerId, acked);
      }
      if (here) _saved.noteSent();
      // A send cannot move the relationship any more — being friends is what
      // made it possible — but it can *reveal* that this device was wrong
      // about it. The server always answers `friends`, so a disagreement here
      // means the local graph is stale, and re-reading it is cheaper than
      // waiting for something else to ask.
      if (FriendshipState.parse(data['state']) != state.stateFor(peerId)) {
        unawaited(loadFriends());
      }
      unawaited(refreshConversations());
      return false;
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[CentralDM] attachment upload failed: $e');
      if (Outbox.canRetry(e.errorCode)) {
        hold();
        return false;
      }
      if (open()) _removePending(pendingId);
      // Central's file space for the account is used up: the one refusal
      // with something the reader can act on, so it is said as it came.
      final full = e.errorCode == ErrorCode.accountStorageFull;
      emit(
        state.copyWith(
          notice: Notice.error(
            full ? e.message : 'Failed to upload attachment',
          ),
        ),
      );
      return open();
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] send failed: $e');
      // No code to read, so no claim that a retry would help.
      if (open()) _removePending(pendingId);
      emit(state.copyWith(notice: Notice.error('Failed to send message')));
      return open();
    } finally {
      _outbox.finished(pendingId);
    }
  }

  /// Keep a send the connection lost, and mark the row so it says so.
  ///
  /// Only ever called for a retryable failure — the refusals go through
  /// [_reportSendFailure], which has something specific to say and nothing to
  /// offer a retry for. Holds whether or not the conversation is still open,
  /// so walking away mid-failure does not lose the message
  /// (`Outbox.restoreInto` brings it back).
  ///
  /// A send that outlived its account — signed out while it was on its way —
  /// is not held: the outbox was emptied with that account, and keeping it
  /// would offer the next one a retry on somebody else's sentence. It is
  /// said instead.
  void _failSend({
    required ChatMessage pending,
    required String myId,
    required OutboxEntry entry,
  }) {
    if (_myUserId != myId) {
      emit(state.copyWith(notice: Notice.error('Your message was not sent.')));
      return;
    }
    _outbox.hold(entry);
    if (state.openPeerId == entry.destination) {
      emit(
        state.copyWith(
          messages: ChatMessageOps.markFailed(state.messages, pending.id),
        ),
      );
    }
  }

  /// Try one held send again — what tapping a "Not sent" row does.
  ///
  /// An attempt that reached central and heard nothing back may have been
  /// stored, so the newest rows are read first: one of them being this
  /// message retires the row instead (`Outbox.retireStored`). Sent again
  /// unread, it reached them twice and spent the quota twice.
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

  void _reportSendFailure(APIResponse response) {
    switch (response.errorCode) {
      case 'quota_exceeded':
        emit(state.copyWith(remaining: 0));
        emit(
          state.copyWith(
            notice: Notice.error(
              'Daily central DM limit reached — continue on a shared '
              'server, or try again tomorrow.',
            ),
          ),
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
        emit(
          state.copyWith(
            notice: Notice.error(
              'You can only message people you are friends with.',
            ),
          ),
        );
      default:
        emit(
          state.copyWith(
            notice: Notice.error(response.error ?? 'Failed to send message'),
          ),
        );
    }
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
        origin: AttachmentLoader.central,
        download: () => _repo.downloadAttachment(
          path: attachment.storagePath,
          keyB64: attachment.keyB64,
          nonceB64: attachment.nonceB64,
          sha256B64: attachment.sha256B64,
          chunkSize: attachment.chunkSize,
        ),
      );

  /// Fetch an attachment for saving. Central's files are small, so it is
  /// fetched whole and handed to [sink] in one piece.
  Future<APIResponse> saveAttachment(
    Attachment attachment,
    BlobSink sink, {
    TransferProgress? onProgress,
  }) async {
    final bytes = await loadAttachment(attachment);
    if (bytes == null) {
      await sink.abort();
      return APIResponse.error("Couldn't download that file.");
    }
    await sink.add(bytes);
    await sink.close();
    onProgress?.call(bytes.length, bytes.length);
    return APIResponse.success(null);
  }

  /// What the message list draws and saves attachments with.
  AttachmentLoader get attachmentLoader => AttachmentLoader(
    origin: AttachmentLoader.central,
    load: loadAttachment,
    save: saveAttachment,
  );
}
