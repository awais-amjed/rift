part of 'central_dm_cubit.dart';

/// Reactions on central DMs. Not E2E — the central server sees who reacted
/// with what (ARCHITECTURE.md §4).
///
/// A message page arrives with its reactions already on it, so this runs only
/// for your own tap. Unlike the self-hosted surfaces there is no reaction
/// doorbell here, so a peer's reaction shows up when the conversation is next
/// opened rather than live.
mixin _CentralDmReactionsMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;

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

    final response = await _repo.toggleReaction(messageId: idNum, emoji: emoji);
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

    final response = await _repo.listReactions(messageIds: [idNum]);
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
}
