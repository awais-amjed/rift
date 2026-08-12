part of 'dm_cubit.dart';

/// The open conversation: opening it, paging its history, and decrypting
/// its rows.
mixin _DmHistoryMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);
  Future<ServerIdentity> _vaultIdentityFor(Server server);
  String? get _localUserId;

  /// The open peer just sent a message — used to clear their typing indicator.
  void _onOpenPeerMessage();

  void _joinPeerTopic(String peerId);
  void _leavePeerTopic();


  Future<void> _fetchLatest(String peerId) async {
    final response = await _serverCubit.listDms(
      peerId: peerId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final decrypted = await _decryptRows(peerId, rows);
    emit(
      state.copyWith(
        messages: decrypted.reversed.toList(),
        hasMoreHistory: data['has_more'] as bool? ?? false,
      ),
    );
  }

  Future<void> _fetchAfterLatest() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;

    final response = await _serverCubit.listDms(
      peerId: peerId,
      afterId: ChatMessageOps.latestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return;

    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .cast<Map<String, dynamic>>();
    if (rows.isEmpty) return;

    final incoming = await _decryptRows(peerId, rows);
    if (incoming.isEmpty) return;

    final result = ChatMessageOps.mergeIncoming(
      current: state.messages,
      incoming: incoming,
    );
    if (result.fresh.isEmpty) return;

    emit(state.copyWith(messages: result.merged));

    if (result.fresh.any((m) => !m.isMine)) _onOpenPeerMessage();
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

    final response = await _serverCubit.listDms(
      peerId: peerId,
      beforeId: ChatMessageOps.oldestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final older = await _decryptRows(peerId, rows);
    emit(
      state.copyWith(
        messages: [...older.reversed, ...state.messages],
        hasMoreHistory: data['has_more'] as bool? ?? false,
        isLoadingMore: false,
      ),
    );
  }

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
    final senderKeyB64 =
        row['sender_public_key'] as String? ?? (isMine ? null : peerSigningKey);
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
        authorAvatarPath: row['sender_avatar_path'] as String?,
        text: body.text,
        attachments: body.attachments,
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: isMine,
        editedAt: DateTime.tryParse('${row['edited_at']}'),
        reactions: ReactionOps.fromRow(row),
      );
    } catch (e) {
      HelperMethods.printDebug('[DM] dropped message ${row['id']}: $e');
      return null;
    }
  }

  /// Opens (or starts) the conversation with [peerId]. [peerChatKey] comes
  /// from the conversation row or the member picker.
  Future<void> openConversation({
    required String peerId,
    required String peerName,
    required String? peerChatKey,
  }) async {
    if (state.openPeerId == peerId && state.chatStatus == DmChatStatus.ready) {
      return;
    }

    emit(
      state.copyWith(
        openPeerId: peerId,
        openPeerName: peerName,
        chatStatus: DmChatStatus.loading,
        messages: const [],
        hasMoreHistory: false,
        clearError: true,
      ),
    );

    final key = await _dmKeyFor(peerId, peerChatKey);
    if (state.openPeerId != peerId) return;
    if (key == null) {
      emit(
        state.copyWith(
          chatStatus: DmChatStatus.error,
          error:
              '$peerName has not enabled encrypted chat yet — they need to '
              'open the app once.',
        ),
      );
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
}
