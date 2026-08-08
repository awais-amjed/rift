part of 'central_dm_cubit.dart';

/// The open central-DM conversation: opening it, paging its history, and
/// decrypting its rows. Sender verification keys come from the directory
/// (TOFU): the peer's `signing_public_key` for their rows, ours for ours.
mixin _CentralDmHistoryMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;
  CryptoRepository get _crypto;
  String? get _myUserId;
  Map<String, String> get _peerSigningKeys;
  Map<String, String> get _peerChatKeys;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);
  Future<ServerIdentity> _signingIdentity();

  /// Implemented by the reactions and send mixins.
  Future<void> refreshReactions();
  Future<void> refreshQuota();

  /// Implemented by the unread mixin.
  void markOpenConversationRead();

  /// The DM context both sides derive independently — order-independent so
  /// each peer computes the same string.
  static String _context(String a, String b) {
    final ids = [a, b]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }

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

    emit(
      state.copyWith(
        openPeerId: peerId,
        openPeerHandle: peerHandle,
        chatStatus: DmChatStatus.loading,
        messages: const [],
        hasMoreHistory: false,
        clearError: true,
      ),
    );

    final key = await _dmKeyFor(peerId, _peerChatKeys[peerId]);
    if (state.openPeerId != peerId) return;
    if (key == null) {
      emit(
        state.copyWith(
          chatStatus: DmChatStatus.error,
          error: '@$peerHandle has no chat keys published.',
        ),
      );
      return;
    }

    await _fetchLatest(peerId);
    if (state.openPeerId != peerId) return;
    emit(state.copyWith(chatStatus: DmChatStatus.ready));
    markOpenConversationRead();
    unawaited(refreshQuota());
  }

  void closeConversation() {
    emit(state.copyWith(closeConversation: true));
  }

  Future<void> _fetchLatest(String peerId) async {
    final response = await _repo.listDms(
      peerId: peerId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return;

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final decrypted = await _decryptRows(peerId, rows);
    emit(
      state.copyWith(
        messages: decrypted.reversed.toList(),
        hasMoreHistory: rows.length == ChatMessageOps.pageSize,
      ),
    );
    unawaited(refreshReactions());
  }

  Future<void> _fetchAfterLatest() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;

    final response = await _repo.listDms(
      peerId: peerId,
      afterId: ChatMessageOps.latestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return;

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return;

    final incoming = await _decryptRows(peerId, rows);
    if (incoming.isEmpty) return;

    final result = ChatMessageOps.mergeIncoming(
      current: state.messages,
      incoming: incoming,
    );
    if (result.fresh.isEmpty) return;

    emit(state.copyWith(messages: result.merged));
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

    final response = await _repo.listDms(
      peerId: peerId,
      beforeId: ChatMessageOps.oldestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final older = await _decryptRows(peerId, rows);
    emit(
      state.copyWith(
        messages: [...older.reversed, ...state.messages],
        hasMoreHistory: rows.length == ChatMessageOps.pageSize,
        isLoadingMore: false,
      ),
    );
    unawaited(refreshReactions());
  }

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

  /// Decrypt + verify one row. Returns null on any failure — a message that
  /// doesn't verify is never rendered.
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
        editedAt: DateTime.tryParse('${row['edited_at']}'),
      );
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] dropped ${row['id']}: $e');
      return null;
    }
  }
}
