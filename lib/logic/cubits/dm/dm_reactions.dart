part of 'dm_cubit.dart';

/// Reactions on server DMs. Not E2E — the server sees who reacted with what
/// (ARCHITECTURE.md §4).
///
/// A message page arrives with its reactions already on it, so nothing here
/// runs on open or on scroll — only when a reaction changes afterwards.
mixin _DmReactionsMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;

  /// Optimistic flip first so the tap feels instant, then reconcile with the
  /// server's authoritative counts.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final peerId = state.openPeerId;
    final idNum = int.tryParse(messageId);
    if (peerId == null || idNum == null) return;

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
      scope: 'dm',
      messageId: idNum,
      emoji: emoji,
    );
    if (state.openPeerId != peerId) return;
    if (!response.success) {
      HelperMethods.showError(error: 'Failed to react');
    }
    await refreshReactionsFor(messageId);
  }

  /// Re-fetch one message's authoritative reactions, leaving the rest alone.
  Future<void> refreshReactionsFor(String messageId) async {
    final peerId = state.openPeerId;
    final idNum = int.tryParse(messageId);
    if (peerId == null || idNum == null) return;

    final response = await _serverCubit.listReactions(
      scope: 'dm',
      messageIds: [idNum],
    );
    if (!response.success || state.openPeerId != peerId) return;
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

  /// Every loaded message — the fallback for a doorbell that didn't name one.
  Future<void> refreshReactions() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    final ids = ChatMessageOps.ackedIds(state.messages);
    if (ids.isEmpty) return;

    final response = await _serverCubit.listReactions(
      scope: 'dm',
      messageIds: ids,
    );
    if (!response.success || state.openPeerId != peerId) return;
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
