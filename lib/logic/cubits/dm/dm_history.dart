part of 'dm_cubit.dart';

/// The open conversation: opening it, and paging its history. Turning the rows
/// into messages is [_DmDecryptMixin].
mixin _DmHistoryMixin on Cubit<DmState>, _DmDecryptMixin {
  /// See the send mixin. Read here to put failed sends back under a freshly
  /// fetched page, and to forget one the server turns out to have stored.
  Outbox get _outbox;

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
        // Anything that failed to send to this peer goes back on the end.
        messages: _outbox.restoreInto(decrypted.reversed.toList(), peerId),
        hasMoreHistory: data['has_more'] as bool? ?? false,
      ),
    );
  }

  Future<void> _fetchAfterLatest() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    // Not while the list is a window into history: "newer than the newest
    // one held" is everything from that point on, and appending it would
    // stitch the live end onto a stretch it does not follow.
    if (state.hasNewerHistory) return;

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

    // A send can time out after the server stored it; when that message comes
    // back, the entry behind the row it retires has to go with it.
    for (final pendingId in result.retired) {
      _outbox.drop(pendingId);
    }
    emit(state.copyWith(messages: result.merged));

    if (result.fresh.any((m) => !m.isMine)) _onOpenPeerMessage();
  }

  /// Look up one message a reply names, without putting it in the list.
  ///
  /// Three outcomes, kept apart on purpose — see [QuotedMessage]. A row that
  /// comes back and fails verification answers `unknown` rather than
  /// `deleted`: it is dropped like any other forgery, and "deleted" would be
  /// a claim about a message this client refuses to believe in.
  Future<QuotedMessage> fetchQuoted(String messageId) async {
    final peerId = state.openPeerId;
    final id = int.tryParse(messageId);
    if (peerId == null || id == null) return const QuotedMessage.unknown();

    final response = await _serverCubit.getDmMessage(messageId: id);
    if (!response.success || state.openPeerId != peerId) {
      return const QuotedMessage.unknown();
    }

    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) return const QuotedMessage.deleted();

    final decrypted = await _decryptRows(peerId, [
      (row as Map).cast<String, dynamic>(),
    ]);
    return decrypted.isEmpty
        ? const QuotedMessage.unknown()
        : QuotedMessage.found(decrypted.first);
  }

  /// Put [messageId] in the list by loading a **window** around it, and
  /// answer whether it worked.
  ///
  /// Two requests and one emit, rather than paging backwards a screen at a
  /// time until it turns up — see `ChannelChatCubit.showAround` for what
  /// that cost. The reader lands on a stretch of history, and
  /// `hasNewerHistory` is what says the list is no longer the live tail.
  Future<bool> showAround(String messageId) async {
    final peerId = state.openPeerId;
    final id = int.tryParse(messageId);
    if (peerId == null || id == null) return false;
    if (state.messages.any((m) => m.id == messageId)) return true;

    emit(state.copyWith(isLoadingMore: true));

    // `beforeId` is exclusive, so the target rides in with the older half
    // rather than being fetched a third time.
    final older = await _serverCubit.listDms(
      peerId: peerId,
      beforeId: id + 1,
      limit: _windowHalf,
    );
    final newer = await _serverCubit.listDms(
      peerId: peerId,
      afterId: id,
      limit: _windowHalf,
    );
    if (state.openPeerId != peerId) return false;
    if (!older.success || !newer.success) {
      emit(state.copyWith(isLoadingMore: false));
      return false;
    }

    final olderData = older.data as Map<String, dynamic>;
    final newerData = newer.data as Map<String, dynamic>;
    final newerRows = (newerData['messages'] as List)
        .cast<Map<String, dynamic>>();

    final before = await _decryptRows(
      peerId,
      (olderData['messages'] as List).cast<Map<String, dynamic>>(),
    );
    final after = await _decryptRows(peerId, newerRows);
    if (state.openPeerId != peerId) return false;

    final window = [...before.reversed, ...after];
    if (!window.any((m) => m.id == messageId)) {
      // There but unshowable — dropped on verification. Leaving the list
      // alone is the honest outcome: there is nothing to land on.
      emit(state.copyWith(isLoadingMore: false));
      return false;
    }

    emit(
      state.copyWith(
        messages: window,
        hasMoreHistory: olderData['has_more'] as bool? ?? false,
        hasNewerHistory: newerRows.length >= _windowHalf,
        isLoadingMore: false,
      ),
    );
    return true;
  }

  /// Half the window a jump lands in — this many either side of the target.
  static const int _windowHalf = 25;

  /// Scroll-down pagination, the mirror of [loadMoreHistory]. Only runs
  /// while the list is a window into history.
  Future<void> loadNewerHistory() async {
    final peerId = state.openPeerId;
    if (peerId == null ||
        !state.hasNewerHistory ||
        state.isLoadingMore ||
        state.messages.isEmpty) {
      return;
    }
    emit(state.copyWith(isLoadingMore: true));

    final response = await _serverCubit.listDms(
      peerId: peerId,
      afterId: ChatMessageOps.latestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final rows = (response.data as Map<String, dynamic>)['messages'] as List;
    final newer = await _decryptRows(peerId, rows.cast<Map<String, dynamic>>());
    emit(
      state.copyWith(
        messages: [...state.messages, ...newer],
        hasNewerHistory: rows.length >= ChatMessageOps.pageSize,
        isLoadingMore: false,
      ),
    );
  }

  /// Leave a history window and go back to the live end of the conversation.
  Future<void> returnToPresent() async {
    final peerId = state.openPeerId;
    if (peerId == null || !state.hasNewerHistory) return;
    emit(state.copyWith(isLoadingMore: true, hasNewerHistory: false));
    await _fetchLatest(peerId);
    if (state.openPeerId == peerId) {
      emit(state.copyWith(isLoadingMore: false));
    }
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
