part of 'channel_chat_cubit.dart';

/// Reactions on channel messages. Not E2E — the server sees who reacted with
/// what (ARCHITECTURE.md §4).
///
/// A message page arrives with its reactions already on it, so nothing here
/// runs on open or on scroll. These are only for a change *after* the page
/// loaded: your own tap, or a doorbell saying someone else's.
mixin _ChannelChatReactionsMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;

  /// Toggle the local user's [emoji] reaction on a message. Applies an
  /// optimistic flip, then reconciles with the server's authoritative counts.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final channelId = state.channelId;
    final idNum = int.tryParse(messageId);
    if (channelId == null || idNum == null) return; // can't react to a pending

    emit(
      state.copyWith(
        messages: ReactionOps.withOptimisticReaction(
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
    if (!response.success) {
      emit(state.copyWith(notice: Notice.error('Failed to react')));
    }
    await refreshReactionsFor(messageId);
  }

  /// Re-fetch the authoritative reactions on one message and merge them in.
  /// Everything else on screen is left alone.
  Future<void> refreshReactionsFor(String messageId) async {
    final channelId = state.channelId;
    final idNum = int.tryParse(messageId);
    if (channelId == null || idNum == null) return;

    final response = await _serverCubit.listReactions(
      scope: 'channel',
      messageIds: [idNum],
    );
    if (!response.success || state.channelId != channelId) return;
    emit(
      state.copyWith(
        messages: ReactionOps.withReactionsFor(
          state.messages,
          messageId: messageId,
          data: response.data as Map<String, dynamic>,
        ),
      ),
    );
  }

  /// Re-fetch reactions for every loaded message.
  ///
  /// The fallback for a doorbell that didn't name a message — a client on an
  /// older build rings without one. Costs a request that grows with how far
  /// the reader has scrolled, which is exactly why the doorbell carries the id.
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
        messages: ReactionOps.withReactions(
          state.messages,
          response.data as Map<String, dynamic>,
        ),
      ),
    );
  }
}
