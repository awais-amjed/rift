part of 'dm_cubit.dart';

/// Over the cubit-part budget and one job: opening a conversation and paging
/// it.
///
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

  /// The open conversation's saved copy — see [SavedConversation].
  SavedConversation get _saved;
  Server? get _savedServer;
  String? get _seed;

  /// Opens (or starts) the conversation with [peerId]. [peerChatKey] comes
  /// from the conversation row or the member picker.
  Future<void> openConversation({
    required String peerId,
    required String peerName,
    required String? peerChatKey,
    bool again = false,
  }) async {
    if (state.openPeerId == peerId && state.chatStatus == DmChatStatus.ready) {
      return;
    }
    // Before the state moves on: the flush reads the conversation being left.
    unawaited(_saved.flush(leaving: true));

    // [again] is a retry over the saved copy: it stays on screen, and so does
    // the composer under it with whatever was typed.
    emit(
      state.copyWith(
        openPeerId: peerId,
        openPeerName: peerName,
        chatStatus: DmChatStatus.loading,
        messages: again ? null : const [],
        hasMoreHistory: again ? null : false,
        clearError: true,
        showingSaved: again ? null : false,
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

    // The key is worked out on this device, so the saved copy can be opened
    // before anything is asked of the server.
    await _drawSaved(peerId);
    if (state.openPeerId != peerId) return;

    _joinPeerTopic(peerId);
    final fetched = await _fetchLatest(peerId);
    if (state.openPeerId != peerId) return;
    // Kept on screen when the page could not be fetched, saying so in the
    // composer's place. Without a saved copy this stays what it always was.
    emit(
      state.copyWith(
        chatStatus: !fetched && state.showingSaved
            ? DmChatStatus.error
            : DmChatStatus.ready,
      ),
    );
  }

  /// Open the conversation again after it failed to load — the saved copy's
  /// "Try again".
  Future<void> retryOpen() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    await openConversation(
      peerId: peerId,
      peerName: state.openPeerName ?? '',
      // Already worked out when it was first opened.
      peerChatKey: null,
      again: state.showingSaved,
    );
  }

  void closeConversation() {
    unawaited(_saved.flush(leaving: true));
    _leavePeerTopic();
    emit(state.copyWith(closeConversation: true));
  }

  Future<void> _drawSaved(String peerId) async {
    final server = _savedServer;
    if (server == null) return;
    final saved = await _saved.open(
      _seed,
      MessageCacheSlot.serverDm(
        supabaseUrl: server.supabaseUrl,
        serverId: server.id,
        peerId: peerId,
      ),
      latestPage: () async {
        // Only while this is still the selected server: the read goes to the
        // selected one, and an empty answer from another would be saved as
        // this conversation having been emptied.
        final selected = _serverCubit.state.selectedServer;
        if (selected?.id != server.id ||
            selected?.supabaseUrl != server.supabaseUrl) {
          return null;
        }
        final response = await _serverCubit.listDms(
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
      state.copyWith(messages: messages.reversed.toList(), showingSaved: true),
    );
  }

  /// Whether the newest page arrived. False leaves whatever was drawn.
  Future<bool> _fetchLatest(String peerId) async {
    final response = await _serverCubit.listDms(
      peerId: peerId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.openPeerId != peerId) return false;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    _saved.replace(rows);
    final decrypted = await _decryptRows(peerId, rows);
    emit(
      state.copyWith(
        // Anything that failed to send to this peer goes back on the end.
        messages: _outbox.restoreInto(decrypted.reversed.toList(), peerId),
        hasMoreHistory: data['has_more'] as bool? ?? false,
        // Replaced outright, so what was deleted since the copy was saved is
        // gone rather than merged back.
        showingSaved: false,
      ),
    );
    return true;
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
    _saved.merge(rows);

    final incoming = await _decryptRows(peerId, rows);
    if (incoming.isEmpty) return;

    final result = ChatMessageOps.mergeIncoming(
      current: state.messages,
      incoming: incoming,
    );
    if (result.fresh.isEmpty) return;

    _outbox.dropRetired(result.retired);
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
    return QuotedMessage.settle(
      response,
      stillOpen: () => state.openPeerId == peerId,
      open: (row) async => (await _decryptRows(peerId, [row])).firstOrNull,
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
    final older = await _serverCubit.listDms(
      peerId: peerId,
      beforeId: id + 1,
      limit: ChatMessageOps.windowHalf,
    );
    final newer = await _serverCubit.listDms(
      peerId: peerId,
      afterId: id,
      limit: ChatMessageOps.windowHalf,
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
    final decrypted = await _decryptRows(peerId, [changed]);
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
