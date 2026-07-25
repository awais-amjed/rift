part of 'central_dm_cubit.dart';

/// Conversation aggregation + open-conversation fetch/decrypt/send for
/// central DMs. Sender verification keys come from the directory (TOFU):
/// the peer's `signing_public_key` for their rows, our own identity for ours.
mixin _CentralDmMessagesMixin on Cubit<CentralDmState> {
  static const _pageSize = 50;

  CentralDmRepository get _repo;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  String? get _myUserId;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);
  Future<ServerIdentity> _signingIdentity();

  /// Fire OS notifications for newly-arrived messages across all conversations.
  void _notifyFromConversations(List<DmConversation> conversations);

  int _pendingCounter = 0;

  /// Signing keys per peer from the directory (base64) — for verification.
  final Map<String, String> _peerSigningKeys = {};

  /// Chat keys per peer from the directory (base64) — for DM derivation.
  final Map<String, String> _peerChatKeys = {};

  int get _latestId => state.messages
      .where((m) => !m.isPending)
      .fold(0, (max, m) => int.parse(m.id) > max ? int.parse(m.id) : max);

  static String _context(String a, String b) {
    final ids = [a, b]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }

  // ──────────────────────────────────────────────────────────
  // Quota
  // ──────────────────────────────────────────────────────────

  Future<void> refreshQuota() async {
    final response = await _repo.getQuota();
    if (isClosed || !response.success) return;
    final data = response.data as Map<String, dynamic>;
    emit(state.copyWith(
      quota: data['quota'] as int?,
      remaining: data['remaining'] as int?,
    ));
  }

  // ──────────────────────────────────────────────────────────
  // Conversations
  // ──────────────────────────────────────────────────────────

  Future<void> refreshConversations() async {
    final myId = _myUserId;
    if (myId == null) return;
    emit(state.copyWith(conversationsLoading: true));

    final response = await _repo.listRecentMessages();
    if (isClosed) return;
    if (!response.success) {
      emit(state.copyWith(conversationsLoading: false));
      return;
    }

    // Newest-first scan → first row per peer is the latest envelope.
    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final latestByPeer = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final peerId = row['sender_id'] == myId
          ? row['recipient_id'] as String
          : row['sender_id'] as String;
      latestByPeer.putIfAbsent(peerId, () => row);
    }

    if (latestByPeer.isEmpty) {
      emit(state.copyWith(conversations: const [], conversationsLoading: false));
      return;
    }

    final profilesResponse =
        await _repo.getProfiles(latestByPeer.keys.toList());
    if (isClosed) return;
    final profiles = <String, Map<String, dynamic>>{};
    if (profilesResponse.success) {
      for (final p
          in (profilesResponse.data as List).cast<Map<String, dynamic>>()) {
        profiles[p['user_id'] as String] = p;
        _peerSigningKeys[p['user_id'] as String] =
            p['signing_public_key'] as String;
        _peerChatKeys[p['user_id'] as String] =
            p['chat_public_key'] as String;
      }
    }

    final conversations = <DmConversation>[];
    for (final entry in latestByPeer.entries) {
      final profile = profiles[entry.key];
      final handle = profile?['handle'] as String? ?? 'unknown';
      final preview = await _decryptRow(
        entry.value,
        peerId: entry.key,
        peerHandle: handle,
      );
      conversations.add(DmConversation(
        peerId: entry.key,
        peerName: handle,
        peerChatPublicKey: profile?['chat_public_key'] as String?,
        peerSigningPublicKey: profile?['signing_public_key'] as String?,
        lastMessage: preview,
      ));
    }
    conversations.sort((a, b) {
      final aId = int.tryParse(a.lastMessage?.id ?? '0') ?? 0;
      final bId = int.tryParse(b.lastMessage?.id ?? '0') ?? 0;
      return bId.compareTo(aId);
    });

    emit(state.copyWith(
      conversations: conversations,
      conversationsLoading: false,
    ));
    _notifyFromConversations(conversations);
  }

  // ──────────────────────────────────────────────────────────
  // Open conversation
  // ──────────────────────────────────────────────────────────

  Future<void> openConversation({
    required String peerId,
    required String peerHandle,
    required String? peerChatKey,
    String? peerSigningKey,
  }) async {
    if (state.openPeerId == peerId && state.chatStatus == DmChatStatus.ready) {
      return;
    }
    if (peerChatKey != null) _peerChatKeys[peerId] = peerChatKey;
    if (peerSigningKey != null) _peerSigningKeys[peerId] = peerSigningKey;

    emit(state.copyWith(
      openPeerId: peerId,
      openPeerHandle: peerHandle,
      chatStatus: DmChatStatus.loading,
      messages: const [],
      hasMoreHistory: false,
      clearError: true,
    ));

    final key = await _dmKeyFor(peerId, _peerChatKeys[peerId]);
    if (state.openPeerId != peerId) return;
    if (key == null) {
      emit(state.copyWith(
        chatStatus: DmChatStatus.error,
        error: '@$peerHandle has no chat keys published.',
      ));
      return;
    }

    await _fetchLatest(peerId);
    if (state.openPeerId != peerId) return;
    emit(state.copyWith(chatStatus: DmChatStatus.ready));
    unawaited(refreshQuota());
  }

  void closeConversation() {
    emit(state.copyWith(closeConversation: true));
  }

  Future<void> _fetchLatest(String peerId) async {
    final response = await _repo.listDms(peerId: peerId, limit: _pageSize);
    if (!response.success || state.openPeerId != peerId) return;

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final decrypted = await _decryptRows(peerId, rows);
    emit(state.copyWith(
      messages: decrypted.reversed.toList(),
      hasMoreHistory: rows.length == _pageSize,
    ));
    unawaited(refreshReactions());
  }

  Future<void> _fetchAfterLatest() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;

    final response = await _repo.listDms(
      peerId: peerId,
      afterId: _latestId,
      limit: _pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return;

    final rows = (response.data as List).cast<Map<String, dynamic>>();
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
    unawaited(refreshReactions());
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

    final response = await _repo.listDms(
      peerId: peerId,
      beforeId: oldestId,
      limit: _pageSize,
    );
    if (!response.success || state.openPeerId != peerId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final older = await _decryptRows(peerId, rows);
    emit(state.copyWith(
      messages: [...older.reversed, ...state.messages],
      hasMoreHistory: rows.length == _pageSize,
      isLoadingMore: false,
    ));
    unawaited(refreshReactions());
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
      final message = await _decryptRow(
        row,
        peerId: peerId,
        peerHandle: state.openPeerHandle ?? 'unknown',
      );
      if (message != null) result.add(message);
    }
    return result;
  }

  Future<ChatMessage?> _decryptRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerHandle,
  }) async {
    final myId = _myUserId;
    if (myId == null) return null;

    final key = await _dmKeyFor(peerId, _peerChatKeys[peerId]);
    if (key == null) return null;

    final senderId = row['sender_id'] as String;
    final isMine = senderId == myId;

    try {
      final Uint8List senderKey;
      if (isMine) {
        senderKey = (await _signingIdentity()).publicKeyBytes;
      } else {
        final signingKeyB64 = _peerSigningKeys[peerId];
        if (signingKeyB64 == null) return null;
        senderKey = CryptoRepository.fromBase64(signingKeyB64);
      }

      final plaintext = await _crypto.openMessage(
        envelope: MessageEnvelope.fromJson(row),
        messageKey: key,
        senderPublicKey: senderKey,
        contextId: _context(myId, peerId),
      );
      if (plaintext == null) return null;

      final body = MessageBody.decode(plaintext);
      return ChatMessage(
        id: '${row['id']}',
        authorId: senderId,
        authorName: isMine ? (state.myHandle ?? 'me') : peerHandle,
        text: body.text,
        attachments: body.attachments,
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: isMine,
      );
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] dropped ${row['id']}: $e');
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
    emit(state.copyWith(messages: [
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
    ]));

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
        contextId: _context(myId, peerId),
        keyVersion: 1,
      );

      final response = await _repo.sendDm(
        recipientId: peerId,
        envelope: envelope.toJson(),
      );
      if (state.openPeerId != peerId) return;

      if (!response.success) {
        _removePending(pendingId);
        if (response.errorCode == 'quota_exceeded') {
          emit(state.copyWith(remaining: 0));
          HelperMethods.showError(
            error: 'Daily central DM limit reached — continue on a shared '
                'server, or try again tomorrow.',
          );
        } else {
          HelperMethods.showError(
            error: response.error ?? 'Failed to send message',
          );
        }
        return;
      }

      final data = response.data as Map<String, dynamic>;
      final acked = ChatMessage(
        id: '${data['id']}',
        authorId: myId,
        authorName: state.myHandle ?? 'me',
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
        quota: data['quota'] as int?,
        remaining: data['remaining'] as int?,
      ));
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

  void _removePending(String pendingId) {
    emit(state.copyWith(
      messages: state.messages.where((m) => m.id != pendingId).toList(),
    ));
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

  // ──────────────────────────────────────────────────────────
  // Reactions (not E2E — server-visible; ARCHITECTURE.md §4)
  // ──────────────────────────────────────────────────────────

  Future<void> toggleReaction(String messageId, String emoji) async {
    final peerId = state.openPeerId;
    final idNum = int.tryParse(messageId);
    if (peerId == null || idNum == null) return;

    _applyOptimisticReaction(messageId, emoji);

    final response = await _repo.toggleReaction(messageId: idNum, emoji: emoji);
    if (state.openPeerId != peerId) return;
    if (!response.success) {
      HelperMethods.showError(error: 'Failed to react');
    }
    await refreshReactions();
  }

  Future<void> refreshReactions() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    final ids = state.messages
        .where((m) => !m.isPending)
        .map((m) => int.tryParse(m.id))
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return;

    final response = await _repo.listReactions(messageIds: ids);
    if (!response.success || state.openPeerId != peerId) return;
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
