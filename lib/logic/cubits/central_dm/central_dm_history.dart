part of 'central_dm_cubit.dart';

/// The open central-DM conversation: opening it, and paging its history.
/// Turning the rows into messages is [_CentralDmDecryptMixin].
mixin _CentralDmHistoryMixin on Cubit<CentralDmState>, _CentralDmDecryptMixin {
  /// See the send mixin. Read here to put failed sends back under a freshly
  /// fetched page, and to forget one the server turns out to have stored.
  Outbox get _outbox;

  CentralDmRepository get _repo;

  /// Implemented by the send mixin.
  Future<void> refreshQuota();

  /// Implemented by the unread mixin.
  void markOpenConversationRead();

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
        friendsOpen: false,
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
    emit(state.copyWith(closeConversation: true, friendsOpen: false));
  }

  /// Show the friends page, closing whatever conversation is open.
  ///
  /// The only navigation on this tier that is not "open a person", and the
  /// only way back to friends from inside a conversation.
  void openFriends() {
    emit(state.copyWith(closeConversation: true, friendsOpen: true));
  }

  Future<void> _fetchLatest(String peerId) async {
    final response = await _repo.listDms(
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

    final response = await _repo.listDms(
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

    // A send can time out after central stored it; when that message comes
    // back, the entry behind the row it retires has to go with it.
    for (final pendingId in result.retired) {
      _outbox.drop(pendingId);
    }
    emit(state.copyWith(messages: result.merged));
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

    final response = await _repo.getDm(messageId: id);
    if (!response.success || state.openPeerId != peerId) {
      return const QuotedMessage.unknown();
    }

    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) return const QuotedMessage.deleted();

    final message = await _decryptRow(
      (row as Map).cast<String, dynamic>(),
      peerId: peerId,
      peerHandle: state.openPeerHandle ?? 'unknown',
    );
    return message == null
        ? const QuotedMessage.unknown()
        : QuotedMessage.found(message);
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
    final older = await _repo.listDms(
      peerId: peerId,
      beforeId: id + 1,
      limit: _windowHalf,
    );
    final newer = await _repo.listDms(
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

    final response = await _repo.listDms(
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

  /// Re-read one message after the peer edited it. Central has no delete
  /// notification (see `CentralDmRepository.subscribeIncoming`), but the row
  /// being gone is still handled — a stale id would otherwise leave a message
  /// on screen that no longer exists.
  Future<void> refreshMessage(String messageId) async {
    final peerId = state.openPeerId;
    final id = int.tryParse(messageId);
    if (peerId == null || id == null) return;
    if (!state.messages.any((m) => m.id == messageId)) return;

    final response = await _repo.getDm(messageId: id);
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

    final message = await _decryptRow(
      (row as Map).cast<String, dynamic>(),
      peerId: peerId,
      peerHandle: state.openPeerHandle ?? 'unknown',
    );
    if (message == null || state.openPeerId != peerId) return;
    emit(
      state.copyWith(
        messages: ChatMessageOps.replaceMessage(state.messages, message),
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

    final response = await _repo.listDms(
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
