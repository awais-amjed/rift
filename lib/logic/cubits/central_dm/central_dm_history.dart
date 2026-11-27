part of 'central_dm_cubit.dart';

/// Over the cubit-part budget and one job: opening a conversation and paging
/// it.
///
/// The open central-DM conversation: opening it, and paging its history.
/// Turning the rows into messages is [_CentralDmDecryptMixin].
mixin _CentralDmHistoryMixin on Cubit<CentralDmState>, _CentralDmDecryptMixin {
  /// Messages a doorbell named that are not on the page, for a quote of one
  /// to be fetched again ([OffPageChanges]).
  final OffPageChanges _offPage = OffPageChanges();

  /// See [OffPageChanges].
  Stream<String> get quoteChanges => _offPage.stream;

  /// The quotes a frame asks about, read at once per conversation.
  late final QuoteBatcher<String> _quotes = QuoteBatcher(_readQuoted);

  /// See the send mixin. Read here to put failed sends back under a freshly
  /// fetched page, and to forget one the server turns out to have stored.
  Outbox get _outbox;

  CentralDmRepository get _repo;

  /// Implemented by the send mixin.
  Future<void> refreshStaleQuota();

  /// Implemented by the unread mixin.
  void markOpenConversationRead();

  /// Implemented by the friends mixin.
  Future<void> _refreshOpenPeerState();

  /// The open conversation's saved copy — see [SavedConversation].
  SavedConversation get _saved;
  String? get _seed;

  /// A message rang while the conversation was opening. The page being
  /// fetched may have been read before it was stored, and the bell is not
  /// rung twice, so the open reads after its page once it is ready.
  bool _rangWhileOpening = false;

  Future<void> openConversation({
    required String peerId,
    required String peerHandle,
    required String? peerChatKey,
    String? peerSigningKey,
    bool again = false,
  }) async {
    if (state.openPeerId == peerId && state.chatStatus == DmChatStatus.ready) {
      return;
    }
    if (peerChatKey != null) _peerChatKeys[peerId] = peerChatKey;
    if (peerSigningKey != null) _peerSigningKeys[peerId] = peerSigningKey;
    // Before the state moves on: the flush reads the conversation being left.
    unawaited(_saved.flush(leaving: true));
    _rangWhileOpening = false;
    final samePeer = state.openPeerId == peerId;

    // Nothing of the last conversation is carried into this one: a history
    // window, a page still loading, or where it stood with its peer. Kept,
    // a window opened in one showed its bar in the next and stopped its
    // arrivals, and a page left loading stopped paging in every one after.
    emit(
      state.copyWith(
        friendsOpen: false,
        openPeerId: peerId,
        openPeerHandle: peerHandle,
        chatStatus: DmChatStatus.loading,
        // [again] is a retry over the saved copy, which stays on screen with
        // the composer under it and whatever was typed.
        messages: again ? null : const [],
        hasMoreHistory: again ? null : false,
        hasNewerHistory: again ? null : false,
        isLoadingMore: false,
        clearError: true,
        loadFailed: false,
        showingSaved: again ? null : false,
        clearOpenPeerState: !samePeer,
      ),
    );
    // A listed conversation's row says where the two of you stand
    // ([CentralDmState.stateFor] reads it first), so only somebody with no
    // row yet — opened from the friends page — has to be asked.
    if (!state.conversations.any((c) => c.peerId == peerId)) {
      unawaited(_refreshOpenPeerState());
    }

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

    // Both keys are already on this device, so the saved copy opens before
    // central is asked anything.
    await _drawSaved(peerId);
    if (state.openPeerId != peerId) return;

    final fetched = await _fetchLatest(peerId);
    if (state.openPeerId != peerId) return;
    // A saved copy is kept on screen when the page could not be fetched,
    // saying so in the composer's place. Without one there is nothing to
    // show, and the conversation says it could not be loaded.
    if (!fetched) {
      emit(
        state.copyWith(
          chatStatus: DmChatStatus.error,
          loadFailed: !state.showingSaved,
        ),
      );
      return;
    }
    emit(state.copyWith(chatStatus: DmChatStatus.ready));
    markOpenConversationRead();
    unawaited(refreshStaleQuota());
    if (_rangWhileOpening) {
      _rangWhileOpening = false;
      unawaited(_fetchAfterLatest());
    }
  }

  /// A message rang for the open conversation — see [_rangWhileOpening].
  void _catchUpOpen() {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        unawaited(_fetchAfterLatest());
      case DmChatStatus.loading:
        _rangWhileOpening = true;
      case DmChatStatus.error || DmChatStatus.closed:
    }
  }

  /// Open the conversation again after it failed to load — the saved copy's
  /// "Try again".
  Future<void> retryOpen() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    await openConversation(
      peerId: peerId,
      peerHandle: state.openPeerHandle ?? '',
      // Both keys were kept when it was first opened.
      peerChatKey: null,
      again: state.showingSaved,
    );
  }

  void closeConversation() {
    unawaited(_saved.flush(leaving: true));
    emit(state.copyWith(closeConversation: true, friendsOpen: false));
  }

  /// Show the friends page, closing whatever conversation is open.
  ///
  /// The only navigation on this tier that is not "open a person", and the
  /// only way back to friends from inside a conversation.
  void openFriends() {
    unawaited(_saved.flush(leaving: true));
    emit(state.copyWith(closeConversation: true, friendsOpen: true));
  }

  Future<void> _drawSaved(String peerId) async {
    final saved = await _saved.open(
      _seed,
      MessageCacheSlot.centralDm(peerId: peerId),
      latestPage: () async {
        final response = await _repo.listDms(
          peerId: peerId,
          limit: ChatMessageOps.pageSize,
        );
        if (!response.success) return null;
        final data = response.data as Map<String, dynamic>;
        return (data['messages'] as List).cast<Map<String, dynamic>>();
      },
    );
    if (saved == null || state.openPeerId != peerId) return;
    final messages = await _decryptRows(
      peerId,
      SavedConversation.rowsOf(saved),
    );
    if (state.openPeerId != peerId ||
        state.chatStatus != DmChatStatus.loading) {
      return;
    }
    emit(
      state.copyWith(
        // With what is still sending, or failed to, on the end.
        messages: _outbox.restoreInto(messages.reversed.toList(), peerId),
        showingSaved: true,
      ),
    );
  }

  /// Whether the newest page arrived. False leaves whatever was drawn.
  Future<bool> _fetchLatest(String peerId) async {
    final response = await _repo.listDms(
      peerId: peerId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return false;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    _saved.replace(rows);
    final decrypted = await _decryptRows(peerId, rows);
    // Opened while these were being read: they are not that conversation's.
    if (state.openPeerId != peerId) return false;
    // A held send this page shows was stored after all is not put back
    // beside itself.
    _outbox.retireStored(peerId, rows);
    emit(
      state.copyWith(
        // Anything that failed to send to this peer goes back on the end.
        // And anything still sending, with how far it has got.
        messages: _outbox.restoreInto(
          decrypted.reversed.toList(),
          peerId,
          fresh: true,
        ),
        hasMoreHistory: data['has_more'] as bool? ?? false,
        // Replaced outright, so what was deleted since the copy was saved is
        // gone rather than merged back.
        showingSaved: false,
      ),
    );
    return true;
  }

  /// What is newer than the newest message held, read once however many
  /// rings ask while a read is out ([CoalescedRefresh]): a burst of messages
  /// was a read each.
  Future<void> _fetchAfterLatest() => _afterLatest();

  late final CoalescedRefresh<void> _afterLatest = CoalescedRefresh(
    _readAfterLatest,
  );

  Future<void> _readAfterLatest() async {
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
    _saved.merge(rows);

    final incoming = await _decryptRows(peerId, rows);
    // Another conversation was opened while they were read.
    if (incoming.isEmpty || state.openPeerId != peerId) return;

    // A held send that is among them was stored after all: its row goes,
    // and the stored one takes its place.
    final stored = _outbox.retireStored(peerId, rows);
    var current = state.messages;
    for (final pendingId in stored.pendingIds) {
      current = ChatMessageOps.removePending(current, pendingId);
    }
    final result = ChatMessageOps.mergeIncoming(
      current: current,
      incoming: incoming,
      claimed: stored.rowIds,
    );
    if (result.fresh.isEmpty) {
      if (stored.pendingIds.isNotEmpty) emit(state.copyWith(messages: current));
      return;
    }

    _outbox.dropRetired(result.retired);
    emit(state.copyWith(messages: result.merged));
  }

  /// The connection is back after dropping: read the newest page again and
  /// fold it into what is loaded ([ChatMessageOps.reconcileNewest]), so what
  /// was edited, deleted, reacted to or pinned meanwhile shows — not only
  /// what was sent. A conversation still opening reads it once it has.
  void _rereadOpen() {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        unawaited(_rereadNewest());
      case DmChatStatus.loading:
        _rangWhileOpening = true;
      case DmChatStatus.error || DmChatStatus.closed:
    }
  }

  Future<void> _rereadNewest() async {
    final peerId = state.openPeerId;
    if (peerId == null || state.hasNewerHistory) return;

    final response = await _repo.listDms(
      peerId: peerId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return;
    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final hasMore = data['has_more'] as bool? ?? false;
    _saved.replace(rows);
    final page = await _decryptRows(peerId, rows);
    if (state.openPeerId != peerId || state.hasNewerHistory) return;

    final stored = _outbox.retireStored(peerId, rows);
    var current = state.messages;
    for (final pendingId in stored.pendingIds) {
      current = ChatMessageOps.removePending(current, pendingId);
    }
    final result = ChatMessageOps.reconcileNewest(
      current: current,
      page: page.reversed.toList(),
      floor: hasMore ? ChatMessageOps.floorOf(rows) : null,
      claimed: stored.rowIds,
    );
    _outbox.dropRetired(result.retired);
    emit(
      state.copyWith(
        messages: result.merged,
        hasMoreHistory: result.replaced ? hasMore : null,
      ),
    );
  }

  /// Look up one message a reply names, without putting it in the list.
  ///
  /// Three outcomes, kept apart on purpose — see [QuotedMessage]. A row that
  /// comes back and fails verification answers `unknown` rather than
  /// `deleted`: it is dropped like any other forgery, and "deleted" would be
  /// a claim about a message this client refuses to believe in.
  ///
  /// Asked together with the other quotes the same frame asks about
  /// ([QuoteBatcher]): a page of replies is one read, not one each.
  Future<QuotedMessage> fetchQuoted(String messageId) async {
    final peerId = state.openPeerId;
    if (peerId == null || int.tryParse(messageId) == null) {
      return const QuotedMessage.unknown();
    }
    return _quotes.lookUp(peerId, messageId);
  }

  Future<Map<String, QuotedMessage>> _readQuoted(
    String peerId,
    List<String> ids,
  ) async {
    final response = await _repo.getDms(
      messageIds: [for (final id in ids) int.parse(id)],
    );
    final peerHandle = state.openPeerHandle ?? 'unknown';
    return QuotedMessage.settleMany(
      response,
      ids: ids,
      stillOpen: () => state.openPeerId == peerId,
      open: (rows) async => [
        for (final m in await Future.wait([
          for (final row in rows)
            _decryptRow(row, peerId: peerId, peerHandle: peerHandle),
        ]))
          ?m,
      ],
    );
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
    // Together: the reader is waiting on the two halves, not one then the other.
    final (older, newer) = await (
      _repo.listDms(
        peerId: peerId,
        beforeId: id + 1,
        limit: ChatMessageOps.windowHalf,
      ),
      _repo.listDms(
        peerId: peerId,
        afterId: id,
        limit: ChatMessageOps.windowHalf,
      ),
    ).wait;
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

    final window = ChatMessageOps.windowAround(
      messageId,
      older: before,
      newer: after,
      newerRowCount: newerRows.length,
    );
    if (window == null) {
      emit(state.copyWith(isLoadingMore: false));
      return false;
    }

    emit(
      state.copyWith(
        messages: window.messages,
        hasMoreHistory: olderData['has_more'] as bool? ?? false,
        hasNewerHistory: window.hasNewer,
        isLoadingMore: false,
      ),
    );
    return true;
  }

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
    if (state.openPeerId != peerId) return;
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
    final fetched = await _fetchLatest(peerId);
    // Not fetched, the list is still the window it was, and says so: called
    // live, arrivals were added to its end and paging on skipped the gap.
    if (state.openPeerId == peerId) {
      emit(
        state.copyWith(
          isLoadingMore: false,
          hasNewerHistory: fetched ? null : true,
        ),
      );
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
    if (!state.messages.any((m) => m.id == messageId)) {
      _offPage.ring(messageId);
      return;
    }

    final response = await _repo.getDm(messageId: id);
    if (!response.success || state.openPeerId != peerId) return;

    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) {
      _saved.remove(messageId);
      emit(
        state.copyWith(
          messages: ChatMessageOps.removeMessage(state.messages, messageId),
        ),
      );
      return;
    }

    final changed = (row as Map).cast<String, dynamic>();
    _saved.update(changed);
    final message = await _decryptRow(
      changed,
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
    if (state.openPeerId != peerId) return;
    emit(
      state.copyWith(
        messages: [...older.reversed, ...state.messages],
        hasMoreHistory: data['has_more'] as bool? ?? false,
        isLoadingMore: false,
      ),
    );
  }
}
