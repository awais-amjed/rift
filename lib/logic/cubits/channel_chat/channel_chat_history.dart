part of 'channel_chat_cubit.dart';

/// Fetching a channel's history: the first page, the catch-up after a
/// doorbell, one row a change named, and the page above when the reader scrolls
/// up.
///
/// What a row *becomes* is `_ChannelChatRowsMixin`'s job — opened, locked or
/// dropped. Everything here only decides which rows to ask for.
///
/// Over the cubit-part budget and one job: which rows to ask for. Each fetch is
/// short; there are five of them.
mixin _ChannelChatHistoryMixin
    on Cubit<ChannelChatState>, _ChannelChatRowsMixin {
  /// Called with messages that just arrived live (not the initial backlog and
  /// not our own sends) so the hub can clear typing state and notify.
  void _onFreshIncoming(List<ChatMessage> incoming);

  /// See the send mixin. Read here to put failed sends back under a freshly
  /// fetched page, and to forget one the server turns out to have stored.
  Outbox get _outbox;

  Future<void> _fetchLatest(String channelId) async {
    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.channelId != channelId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    // Rows arrive newest-first; decrypt then restore oldest→newest order.
    final decrypted = await _decryptRows(channelId, rows);
    emit(
      state.copyWith(
        // Anything that failed to send in this channel goes back on the end.
        // Without this a "Not sent" row lasts exactly until the first click
        // elsewhere, which is the loss the outbox exists to stop.
        messages: _outbox.restoreInto(decrypted.reversed.toList(), channelId),
        hasMoreHistory: data['has_more'] as bool? ?? false,
      ),
    );
  }

  /// Catch up on rows newer than what we hold (doorbell / reconnect path).
  Future<void> _fetchAfterLatest() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    // Not while the list is a window into history. "Newer than the newest
    // one held" is the whole conversation from that point on, and appending
    // it would stitch the live end onto a stretch it does not follow.
    if (state.hasNewerHistory) return;

    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      afterId: ChatMessageOps.latestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.channelId != channelId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return;

    final incoming = await _decryptRows(channelId, rows); // oldest-first
    if (incoming.isEmpty) return;

    final result = ChatMessageOps.mergeIncoming(
      current: state.messages,
      incoming: incoming,
    );
    if (result.fresh.isEmpty) return;

    // A send can time out *after* the server stored it. When that message comes
    // back the merge retires the row it belongs to — and the outbox entry
    // behind it has to go too, or reopening the channel would offer to send a
    // message that is already in it.
    for (final pendingId in result.retired) {
      _outbox.drop(pendingId);
    }
    emit(state.copyWith(messages: result.merged));

    final freshIncoming = result.fresh.where((m) => !m.isMine).toList();
    if (freshIncoming.isNotEmpty) _onFreshIncoming(freshIncoming);
  }

  /// Fetch one message by id, when a doorbell named it and the catch-up read
  /// did not bring it back.
  ///
  /// [_fetchAfterLatest] asks for rows newer than the newest one held, so a
  /// message missed once is unreachable the moment a later one arrives: the
  /// only thing that would show it again is reopening the channel. This asks
  /// for that row alone.
  Future<void> fetchMissingMessage(String messageId) async {
    final channelId = state.channelId;
    final id = int.tryParse(messageId);
    if (channelId == null || id == null) return;
    if (state.messages.any((message) => message.id == messageId)) return;
    // A row that arrived while the reader is back in history belongs after
    // messages that are not loaded, not at the end of what is.
    if (state.hasNewerHistory) return;

    final response = await _serverCubit.getChatMessage(
      channelId: channelId,
      messageId: id,
    );
    if (!response.success || state.channelId != channelId) return;

    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) return; // deleted in the meantime
    final decrypted = await _decryptRows(channelId, [
      (row as Map).cast<String, dynamic>(),
    ]);
    if (decrypted.isEmpty || state.channelId != channelId) return;

    final result = ChatMessageOps.mergeIncoming(
      current: state.messages,
      incoming: decrypted,
    );
    if (result.fresh.isEmpty) return;
    emit(state.copyWith(messages: result.merged));
    final freshIncoming = result.fresh.where((m) => !m.isMine).toList();
    if (freshIncoming.isNotEmpty) _onFreshIncoming(freshIncoming);
  }

  /// Look up one message a reply names, without putting it in the list.
  ///
  /// Deliberately not [fetchMissingMessage]: that merges the row into the
  /// conversation, and a message from five hundred back sitting directly
  /// above a recent one is a hole in the history drawn as if it were not
  /// there. This answers the quote and nothing else.
  ///
  /// The three outcomes are the point — see [QuotedMessage]. A row that
  /// comes back and fails verification is `unknown`, not `deleted`: it is
  /// dropped like any other forgery, and saying "deleted" would be claiming
  /// something about a message this client refuses to believe in.
  Future<QuotedMessage> fetchQuoted(String messageId) async {
    final channelId = state.channelId;
    final id = int.tryParse(messageId);
    if (channelId == null || id == null) return const QuotedMessage.unknown();

    final response = await _serverCubit.getChatMessage(
      channelId: channelId,
      messageId: id,
    );
    return QuotedMessage.settle(
      response,
      stillOpen: () => state.channelId == channelId,
      open: (row) async => (await _decryptRows(channelId, [row])).firstOrNull,
    );
  }

  /// Put [messageId] in the list by loading a **window** around it, and
  /// answer whether it worked.
  ///
  /// This used to page backwards one screen at a time until the message
  /// turned up, which is the obvious thing and the wrong one. Answering a
  /// message a thousand back meant twenty-odd round trips in a row, twenty-odd
  /// rebuilds of a list growing by fifty each time, and a thousand messages
  /// left in memory to show one — about a second of locked UI, and the
  /// history of the entire channel as a side effect.
  ///
  /// So: two requests, one emit, fifty rows. The reader lands on a stretch of
  /// history rather than at the end of a long crawl through it, and
  /// [ChannelChatState.hasNewerHistory] is what says the list is no longer
  /// the live tail.
  Future<bool> showAround(String messageId) async {
    final channelId = state.channelId;
    final id = int.tryParse(messageId);
    if (channelId == null || id == null) return false;
    if (state.messages.any((m) => m.id == messageId)) return true;

    emit(state.copyWith(isLoadingMore: true));

    // The message itself comes with the older half: `beforeId` is exclusive,
    // so it is asked for by its own id plus one rather than fetched a third
    // time.
    final older = await _serverCubit.listChatMessages(
      channelId: channelId,
      beforeId: id + 1,
      limit: _windowHalf,
    );
    final newer = await _serverCubit.listChatMessages(
      channelId: channelId,
      afterId: id,
      limit: _windowHalf,
    );
    if (state.channelId != channelId) return false;
    if (!older.success || !newer.success) {
      emit(state.copyWith(isLoadingMore: false));
      return false;
    }

    final olderData = older.data as Map<String, dynamic>;
    final newerData = newer.data as Map<String, dynamic>;
    final olderRows = (olderData['messages'] as List)
        .cast<Map<String, dynamic>>();
    final newerRows = (newerData['messages'] as List)
        .cast<Map<String, dynamic>>();

    final before = await _decryptRows(channelId, olderRows); // newest-first
    final after = await _decryptRows(channelId, newerRows);
    if (state.channelId != channelId) return false;

    final window = [...before.reversed, ...after];
    if (!window.any((m) => m.id == messageId)) {
      // The row is there but this client will not show it — dropped on
      // verification, or sealed under a key it does not hold. Leaving the
      // list alone is the honest outcome: there is nothing to land on.
      emit(state.copyWith(isLoadingMore: false));
      return false;
    }

    emit(
      state.copyWith(
        messages: window,
        hasMoreHistory: olderData['has_more'] as bool? ?? false,
        // A full page of newer rows means the window stops short of the
        // present. Asking for one more than fits would be a third request to
        // learn something the page count already says.
        hasNewerHistory: newerRows.length >= _windowHalf,
        isLoadingMore: false,
      ),
    );
    return true;
  }

  /// Half the window a jump lands in — this many either side of the target.
  static const int _windowHalf = 25;

  /// Scroll-down pagination, the mirror of [loadMoreHistory]. Only ever runs
  /// while the list is a window into history; at the live tail there is
  /// nothing newer to fetch and [ChannelChatState.hasNewerHistory] is false.
  Future<void> loadNewerHistory() async {
    final channelId = state.channelId;
    if (channelId == null ||
        !state.hasNewerHistory ||
        state.isLoadingMore ||
        state.messages.isEmpty) {
      return;
    }
    emit(state.copyWith(isLoadingMore: true));

    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      afterId: ChatMessageOps.latestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.channelId != channelId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final rows = (response.data as Map<String, dynamic>)['messages'] as List;
    final newer = await _decryptRows(
      channelId,
      rows.cast<Map<String, dynamic>>(),
    );
    emit(
      state.copyWith(
        messages: [...state.messages, ...newer],
        // Short page: there was nothing more to come, so this is the present
        // again and the way back can go away.
        hasNewerHistory: rows.length >= ChatMessageOps.pageSize,
        isLoadingMore: false,
      ),
    );
  }

  /// Leave a history window and go back to the live end of the channel.
  Future<void> returnToPresent() async {
    final channelId = state.channelId;
    if (channelId == null || !state.hasNewerHistory) return;
    emit(state.copyWith(isLoadingMore: true, hasNewerHistory: false));
    await _fetchLatest(channelId);
    if (state.channelId == channelId) {
      emit(state.copyWith(isLoadingMore: false));
    }
  }

  /// Re-read one message a change doorbell named, and apply whatever happened
  /// to it: an edit swaps the row in place, a delete takes it off the list.
  ///
  /// Both used to be invisible to anyone already in the channel. The doorbell
  /// they rang sent everyone to [_fetchAfterLatest], which asks for rows
  /// *newer* than the newest one held — and an edited message is not a new one,
  /// so the answer was always empty. The change showed up when the channel was
  /// next opened, and not before.
  ///
  /// A message outside the loaded window is left alone, and a row that fails
  /// verification is kept rather than dropped: the ping is best-effort, and
  /// reopening the channel re-reads everything properly.
  Future<void> refreshMessage(String messageId) async {
    final channelId = state.channelId;
    final id = int.tryParse(messageId);
    if (channelId == null || id == null) return;
    if (!state.messages.any((m) => m.id == messageId)) return;

    final response = await _serverCubit.getChatMessage(
      channelId: channelId,
      messageId: id,
    );
    if (!response.success || state.channelId != channelId) return;

    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) {
      emit(
        state.copyWith(
          messages: ChatMessageOps.removeMessage(state.messages, messageId),
        ),
      );
      return;
    }

    final decrypted = await _decryptRows(channelId, [
      (row as Map).cast<String, dynamic>(),
    ]);
    if (decrypted.isEmpty || state.channelId != channelId) return;
    emit(
      state.copyWith(
        messages: ChatMessageOps.replaceMessage(
          state.messages,
          decrypted.single,
        ),
      ),
    );
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

    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      beforeId: ChatMessageOps.oldestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.channelId != channelId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final older = await _decryptRows(channelId, rows); // newest-first page
    emit(
      state.copyWith(
        messages: [...older.reversed, ...state.messages],
        hasMoreHistory: data['has_more'] as bool? ?? false,
        isLoadingMore: false,
      ),
    );
  }
}
