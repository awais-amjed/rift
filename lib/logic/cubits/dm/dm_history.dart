part of 'dm_cubit.dart';

/// The open conversation: opening it, and paging its history. Turning the rows
/// into messages is [_DmDecryptMixin].
mixin _DmHistoryMixin on Cubit<DmState>, _DmDecryptMixin {
  /// The open peer just sent a message — used to clear their typing indicator.
  void _onOpenPeerMessage();

  void _joinPeerTopic(String peerId);
  void _leavePeerTopic();

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

  /// Re-read one message the peer said changed, and apply what happened: an
  /// edit swaps it in place, a delete takes it off the list.
  ///
  /// Neither reached an open conversation before — the DM edit path rang no
  /// doorbell at all, so the peer saw the old text until they reopened.
  ///
  /// A message outside the loaded window is left alone, and a row that fails
  /// verification is kept rather than dropped.
  Future<void> refreshMessage(String messageId) async {
    final peerId = state.openPeerId;
    final id = int.tryParse(messageId);
    if (peerId == null || id == null) return;
    if (!state.messages.any((m) => m.id == messageId)) return;

    final response = await _serverCubit.getDmMessage(messageId: id);
    if (!response.success || state.openPeerId != peerId) return;

    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) {
      emit(
        state.copyWith(
          messages: ChatMessageOps.removeMessage(state.messages, messageId),
        ),
      );
      return;
    }

    final decrypted = await _decryptRows(peerId, [
      (row as Map).cast<String, dynamic>(),
    ]);
    if (decrypted.isEmpty || state.openPeerId != peerId) return;
    emit(
      state.copyWith(
        messages: ChatMessageOps.replaceMessage(
          state.messages,
          decrypted.single,
        ),
      ),
    );
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
}
