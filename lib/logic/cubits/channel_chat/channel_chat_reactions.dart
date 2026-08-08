part of 'channel_chat_cubit.dart';

/// Reactions on channel messages. Not E2E — the server sees who reacted with
/// what (ARCHITECTURE.md §4).
mixin _ChannelChatReactionsMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  void _ringReactionDoorbell();

  /// Toggle the local user's [emoji] reaction on a message. Applies an
  /// optimistic flip, then reconciles with the server's authoritative counts.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final channelId = state.channelId;
    final idNum = int.tryParse(messageId);
    if (channelId == null || idNum == null) return; // can't react to a pending

    emit(
      state.copyWith(
        messages: ChatMessageOps.withOptimisticReaction(
          state.messages,
          messageId: messageId,
          emoji: emoji,
        ),
      ),
    );

    final response = await _serverCubit.toggleReaction(
      scope: 'channel',
      messageId: idNum,
      emoji: emoji,
    );
    if (state.channelId != channelId) return;
    if (response.success) {
      _ringReactionDoorbell();
    } else {
      HelperMethods.showError(error: 'Failed to react');
    }
    await refreshReactions();
  }

  /// Re-fetch authoritative reactions for the loaded messages and merge them in
  /// (message content/order untouched). Called after a page load and whenever a
  /// reaction doorbell fires.
  Future<void> refreshReactions() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    final ids = ChatMessageOps.ackedIds(state.messages);
    if (ids.isEmpty) return;

    final response = await _serverCubit.listReactions(
      scope: 'channel',
      messageIds: ids,
    );
    if (!response.success || state.channelId != channelId) return;
    emit(
      state.copyWith(
        messages: ChatMessageOps.withReactions(
          state.messages,
          response.data as Map<String, dynamic>,
        ),
      ),
    );
  }
}
