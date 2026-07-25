part of 'dm_cubit.dart';

/// Conversation list + open-conversation fetch/decrypt/send.
mixin _DmMessagesMixin on Cubit<DmState> {
  static const _pageSize = 50;

  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);
  Future<ServerIdentity> _vaultIdentityFor(Server server);
  void _joinPeerTopic(String peerId);
  void _leavePeerTopic();
  void _ringPeerDoorbell();

  /// Fire OS notifications for newly-arrived messages across all conversations.
  void _notifyFromConversations(List<DmConversation> conversations);

  /// The open peer just sent a message — used to clear their typing indicator.
  void _onOpenPeerMessage();

  int _pendingCounter = 0;

  String? get _localUserId => _serverCubit.state.selectedServer?.user?.id;

  int get _latestId => state.messages
      .where((m) => !m.isPending)
      .fold(0, (max, m) => int.parse(m.id) > max ? int.parse(m.id) : max);

  // ──────────────────────────────────────────────────────────
  // Conversation list
  // ──────────────────────────────────────────────────────────

  Future<void> refreshConversations() async {
    final localUserId = _localUserId;
    if (localUserId == null) return;
    emit(state.copyWith(conversationsLoading: true));

    final response = await _serverCubit.listDmConversations();
    if (isClosed) return;
    if (!response.success) {
      emit(state.copyWith(conversationsLoading: false));
      return;
    }

    final rows =
        ((response.data as Map<String, dynamic>)['conversations'] as List)
            .cast<Map<String, dynamic>>();

    final conversations = <DmConversation>[];
    for (final row in rows) {
      final peerId = row['peer_id'] as String;
      final peerName = row['peer_name'] as String? ?? 'Unknown';
      final peerChatKey = row['peer_chat_public_key'] as String?;
      final peerSigningKey = row['peer_public_key'] as String?;

      ChatMessage? preview;
      final last = row['last_message'] as Map<String, dynamic>?;
      if (last != null) {
        preview = await _decryptDmRow(
          last,
          peerId: peerId,
          peerName: peerName,
          peerChatKey: peerChatKey,
          peerSigningKey: peerSigningKey,
        );
      }
      conversations.add(DmConversation(
        peerId: peerId,
        peerName: peerName,
        peerChatPublicKey: peerChatKey,
        peerSigningPublicKey: peerSigningKey,
        lastMessage: preview,
      ));
    }

    emit(state.copyWith(
      conversations: conversations,
      conversationsLoading: false,
    ));
    _notifyFromConversations(conversations);
  }

  // ──────────────────────────────────────────────────────────
  // Open conversation
  // ──────────────────────────────────────────────────────────

  /// Opens (or starts) the conversation with [peerId]. [peerChatKey] comes
  /// from the conversation row or the member picker.
  Future<void> openConversation({
    required String peerId,
    required String peerName,
    required String? peerChatKey,
  }) async {
    if (state.openPeerId == peerId &&
        state.chatStatus == DmChatStatus.ready) {
      return;
    }

    emit(state.copyWith(
      openPeerId: peerId,
      openPeerName: peerName,
      chatStatus: DmChatStatus.loading,
      messages: const [],
      hasMoreHistory: false,
      clearError: true,
    ));

    final key = await _dmKeyFor(peerId, peerChatKey);
    if (state.openPeerId != peerId) return;
    if (key == null) {
      emit(state.copyWith(
        chatStatus: DmChatStatus.error,
        error: '$peerName has not enabled encrypted chat yet — they need to '
            'open the app once.',
      ));
      return;
    }

    _joinPeerTopic(peerId);
    await _fetchLatest(peerId);
    if (state.openPeerId != peerId) return;
    emit(state.copyWith(chatStatus: DmChatStatus.ready));
  }

  void closeConversation() {
    _leavePeerTopic();
    emit(state.copyWith(closeConversation: true));
  }

  Future<void> _fetchLatest(String peerId) async {
    final response =
        await _serverCubit.listDms(peerId: peerId, limit: _pageSize);
    if (!response.success || state.openPeerId != peerId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final decrypted = await _decryptRows(peerId, rows);
    emit(state.copyWith(
      messages: decrypted.reversed.toList(),
      hasMoreHistory: data['has_more'] as bool? ?? false,
    ));
  }

  Future<void> _fetchAfterLatest() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;

    final response = await _serverCubit.listDms(
      peerId: peerId,
      afterId: _latestId,
      limit: _pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return;

    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .cast<Map<String, dynamic>>();
    if (rows.isEmpty) return;

    final incoming = await _decryptRows(peerId, rows);
    if (incoming.isEmpty) return;

    final known =
        state.messages.where((m) => !m.isPending).map((m) => m.id).toSet();
    final fresh = incoming.where((m) => !known.contains(m.id)).toList();
    if (fresh.isEmpty) return;

    final freshMineTexts =
        fresh.where((m) => m.isMine).map((m) => m.text).toSet();
    final kept = state.messages
        .where((m) =>
            !(m.isPending && m.isMine && freshMineTexts.contains(m.text)))
        .toList();

    emit(state.copyWith(messages: [...kept, ...fresh]));

    if (fresh.any((m) => !m.isMine)) _onOpenPeerMessage();
  }

  Future<void> loadMoreHistory() async {
    final peerId = state.openPeerId;
    if (peerId == null ||
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

    final response = await _serverCubit.listDms(
      peerId: peerId,
      beforeId: oldestId,
      limit: _pageSize,
    );
    if (!response.success || state.openPeerId != peerId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final older = await _decryptRows(peerId, rows);
    emit(state.copyWith(
      messages: [...older.reversed, ...state.messages],
      hasMoreHistory: data['has_more'] as bool? ?? false,
      isLoadingMore: false,
    ));
  }

  // ──────────────────────────────────────────────────────────
  // Decryption
  // ──────────────────────────────────────────────────────────

  Future<List<ChatMessage>> _decryptRows(
    String peerId,
    List<Map<String, dynamic>> rows,
  ) async {
    final result = <ChatMessage>[];
    for (final row in rows) {
      final message = await _decryptDmRow(
        row,
        peerId: peerId,
        peerName: state.openPeerName ?? 'Unknown',
        peerChatKey: null, // key is already cached from openConversation
        peerSigningKey: null, // per-row attested key is used instead
      );
      if (message != null) result.add(message);
    }
    return result;
  }

  /// Decrypt + verify one DM row. Verification uses the row's server-attested
  /// sender key when present, else [peerSigningKey]. Returns null on any
  /// failure — never rendered.
  Future<ChatMessage?> _decryptDmRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerName,
    required String? peerChatKey,
    required String? peerSigningKey,
  }) async {
    final localUserId = _localUserId;
    if (localUserId == null) return null;

    final key = await _dmKeyFor(peerId, peerChatKey);
    if (key == null) return null;

    final senderId = row['sender_id'] as String;
    final isMine = senderId == localUserId;
    final senderKeyB64 = row['sender_public_key'] as String? ??
        (isMine ? null : peerSigningKey);
    if (senderKeyB64 == null && !isMine) return null;

    try {
      // For rows lacking an attested sender key (conversation previews of our
      // own messages), fall back to our own signing key.
      final Uint8List senderKey;
      if (senderKeyB64 != null) {
        senderKey = CryptoRepository.fromBase64(senderKeyB64);
      } else {
        final server = _serverCubit.state.selectedServer!;
        final identity = await _vaultIdentityFor(server);
        senderKey = identity.publicKeyBytes;
      }

      final plaintext = await _crypto.openMessage(
        envelope: MessageEnvelope.fromJson(row),
        messageKey: key,
        senderPublicKey: senderKey,
        contextId: DmCubit.conversationContext(localUserId, peerId),
      );
      if (plaintext == null) return null;

      final body = MessageBody.decode(plaintext);
      return ChatMessage(
        id: '${row['id']}',
        authorId: senderId,
        authorName: isMine
            ? (_serverCubit.state.selectedServer?.user?.displayName ?? 'Me')
            : (row['sender_name'] as String? ?? peerName),
        text: body.text,
        attachments: body.attachments,
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: isMine,
      );
    } catch (e) {
      HelperMethods.printDebug('[DM] dropped message ${row['id']}: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Sending
  // ──────────────────────────────────────────────────────────

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
      final scope =
          DmCubit.conversationContext(user.id, peerId).replaceAll(':', '_');
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
}
