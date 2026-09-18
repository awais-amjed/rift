part of 'channel_chat_cubit.dart';

/// Fetching a channel's history: the first page, the catch-up after a
/// doorbell, one row a change named, and the page above when the reader scrolls
/// up.
///
/// What a row *becomes* is `_ChannelChatRowsMixin`'s job — opened, locked or
/// dropped. Everything here only decides which rows to ask for.
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
