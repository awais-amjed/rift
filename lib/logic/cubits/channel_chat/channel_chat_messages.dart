part of 'channel_chat_cubit.dart';

/// Message fetch/decrypt/send. Envelopes are opened with the key version they
/// were sealed under; anything failing signature verification is dropped.
mixin _ChatMessagesMixin on Cubit<ChannelChatState> {
  static const _pageSize = 50;

  ServerCubit get _serverCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  int get _currentKeyVersion;
  void _ringDoorbell();
  void _ringReactionDoorbell();

  /// Called with messages that just arrived live (not the initial backlog and
  /// not our own sends) so the hub can clear typing state and notify.
  void _onFreshIncoming(List<ChatMessage> incoming);

  int _pendingCounter = 0;

  /// The newest server-acknowledged message id (pending ids aren't numeric).
  int get _latestId => state.messages
      .where((m) => !m.isPending)
      .fold(0, (max, m) => int.parse(m.id) > max ? int.parse(m.id) : max);

  // ──────────────────────────────────────────────────────────
  // Fetching
  // ──────────────────────────────────────────────────────────

  Future<void> _fetchLatest(String channelId) async {
    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      limit: _pageSize,
    );
    if (!response.success || state.channelId != channelId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    // Rows arrive newest-first; decrypt then restore oldest→newest order.
    final decrypted = await _decryptRows(channelId, rows);
    emit(state.copyWith(
      messages: decrypted.reversed.toList(),
      hasMoreHistory: data['has_more'] as bool? ?? false,
    ));
    unawaited(refreshReactions());
  }

  /// Catch up on rows newer than what we hold (doorbell / reconnect path).
  Future<void> _fetchAfterLatest() async {
    final channelId = state.channelId;
    if (channelId == null) return;

    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      afterId: _latestId,
      limit: _pageSize,
    );
    if (!response.success || state.channelId != channelId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return;

    final incoming = await _decryptRows(channelId, rows); // oldest-first
    if (incoming.isEmpty) return;

    // Merge: drop rows we already hold (own send acked earlier), and drop a
    // pending bubble only when its exact content arrived from the server —
    // other in-flight sends keep their bubbles.
    final known = state.messages.where((m) => !m.isPending).map((m) => m.id).toSet();
    final fresh = incoming.where((m) => !known.contains(m.id)).toList();
    if (fresh.isEmpty) return;

    final freshMineTexts =
        fresh.where((m) => m.isMine).map((m) => m.text).toSet();
    final kept = state.messages
        .where((m) =>
            !(m.isPending && m.isMine && freshMineTexts.contains(m.text)))
        .toList();

    emit(state.copyWith(messages: [...kept, ...fresh]));
    unawaited(refreshReactions());

    final freshIncoming = fresh.where((m) => !m.isMine).toList();
    if (freshIncoming.isNotEmpty) _onFreshIncoming(freshIncoming);
  }

  /// Scroll-up pagination: prepend the page before the oldest loaded row.
  Future<void> loadMoreHistory() async {
    final channelId = state.channelId;
    if (channelId == null ||
        !state.hasMoreHistory ||
        state.isLoadingMore ||
        state.messages.isEmpty) {
      return;
    }
    emit(state.copyWith(isLoadingMore: true));

    final oldestId = state.messages
        .where((m) => !m.isPending)
        .map((m) => int.parse(m.id))
        .fold(0x7fffffffffffffff, (min, id) => id < min ? id : min);

    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      beforeId: oldestId,
      limit: _pageSize,
    );
    if (!response.success || state.channelId != channelId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final older = await _decryptRows(channelId, rows); // newest-first page
    emit(state.copyWith(
      messages: [...older.reversed, ...state.messages],
      hasMoreHistory: data['has_more'] as bool? ?? false,
      isLoadingMore: false,
    ));
    unawaited(refreshReactions());
  }

  // ──────────────────────────────────────────────────────────
  // Decryption
  // ──────────────────────────────────────────────────────────

  /// Decrypt + verify a batch of envelope rows, preserving input order.
  /// Rows we can't decrypt (missing key version) or that fail verification
  /// are dropped — a forged or tampered message is never rendered.
  Future<List<ChatMessage>> _decryptRows(
    String channelId,
    List<Map<String, dynamic>> rows,
  ) async {
    final localUserId = _serverCubit.state.selectedServer?.user?.id;
    final result = <ChatMessage>[];

    for (final row in rows) {
      final keyVersion = row['key_version'] as int;
      final key = _keys[keyVersion];
      final senderKeyB64 = row['sender_public_key'] as String?;
      if (key == null || senderKeyB64 == null) continue;

      try {
        final plaintext = await _crypto.openMessage(
          envelope: MessageEnvelope.fromJson(row),
          messageKey: key,
          senderPublicKey: CryptoRepository.fromBase64(senderKeyB64),
          contextId: channelId,
        );
        if (plaintext == null) {
          HelperMethods.printDebug(
            '[Chat] dropped message ${row['id']}: bad signature',
          );
          continue;
        }
        final body = MessageBody.decode(plaintext);
        result.add(ChatMessage(
          id: '${row['id']}',
          authorId: row['sender_id'] as String,
          authorName: row['sender_name'] as String? ?? 'Unknown',
          text: body.text,
          attachments: body.attachments,
          sentAt: DateTime.parse(row['created_at'] as String),
          isMine: row['sender_id'] == localUserId,
        ));
      } catch (e) {
        HelperMethods.printDebug('[Chat] dropped message ${row['id']}: $e');
      }
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────
  // Sending
  // ──────────────────────────────────────────────────────────

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
    emit(state.copyWith(messages: [
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
    ]));

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
        HelperMethods.showError(
          error: response.error ?? 'Failed to send message',
        );
        return;
      }

      final data = response.data as Map<String, dynamic>;
      final acked = ChatMessage(
        id: '${data['id']}',
        authorId: user.id,
        authorName: user.displayName,
        text: trimmed,
        attachments: uploaded,
        sentAt: DateTime.parse(data['created_at'] as String),
        isMine: true,
      );
      emit(state.copyWith(
        messages: [
          for (final m in state.messages)
            if (m.id != pendingId) m else acked,
        ],
      ));
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
    emit(state.copyWith(
      messages: state.messages.where((m) => m.id != pendingId).toList(),
    ));
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

  // ──────────────────────────────────────────────────────────
  // Reactions (not E2E — server-visible; ARCHITECTURE.md §4)
  // ──────────────────────────────────────────────────────────

  /// Toggle the local user's [emoji] reaction on a message. Applies an
  /// optimistic flip, then reconciles with the server's authoritative counts.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final channelId = state.channelId;
    final idNum = int.tryParse(messageId);
    if (channelId == null || idNum == null) return; // can't react to a pending

    _applyOptimisticReaction(messageId, emoji);

    final response = await _serverCubit.toggleReaction(
      scope: 'channel',
      channelId: channelId,
      messageId: idNum,
      emoji: emoji,
    );
    if (state.channelId != channelId) return;
    if (response.success) {
      _ringReactionDoorbell();
    } else {
      HelperMethods.showError(error: 'Failed to react');
    }
    await refreshReactions();
  }

  /// Re-fetch authoritative reactions for the loaded messages and merge them in
  /// (message content/order untouched). Called after a page load and whenever a
  /// reaction doorbell fires.
  Future<void> refreshReactions() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    final ids = state.messages
        .where((m) => !m.isPending)
        .map((m) => int.tryParse(m.id))
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return;

    final response = await _serverCubit.listReactions(
      scope: 'channel',
      channelId: channelId,
      messageIds: ids,
    );
    if (!response.success || state.channelId != channelId) return;
    _mergeReactions(response.data as Map<String, dynamic>);
  }

  void _mergeReactions(Map<String, dynamic> data) {
    final raw = (data['reactions'] as Map).cast<String, dynamic>();
    emit(state.copyWith(
      messages: state.messages.map((m) {
        final list = raw[m.id];
        final reactions = list == null
            ? const <MessageReaction>[]
            : (list as List)
                .cast<Map<String, dynamic>>()
                .map(MessageReaction.fromJson)
                .toList();
        return m.copyWith(reactions: reactions);
      }).toList(),
    ));
  }

  void _applyOptimisticReaction(String messageId, String emoji) {
    emit(state.copyWith(
      messages: state.messages.map((m) {
        if (m.id != messageId) return m;
        final list = [...m.reactions];
        final idx = list.indexWhere((r) => r.emoji == emoji);
        if (idx == -1) {
          list.add(MessageReaction(emoji: emoji, count: 1, mine: true));
        } else {
          final r = list[idx];
          if (r.mine) {
            final c = r.count - 1;
            if (c <= 0) {
              list.removeAt(idx);
            } else {
              list[idx] = MessageReaction(emoji: emoji, count: c, mine: false);
            }
          } else {
            list[idx] =
                MessageReaction(emoji: emoji, count: r.count + 1, mine: true);
          }
        }
        return m.copyWith(reactions: list);
      }).toList(),
    ));
  }
}
