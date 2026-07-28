part of 'central_dm_cubit.dart';

/// Reactions on central DMs. Not E2E — the central server sees who reacted
/// with what (ARCHITECTURE.md §4).
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
        messages: ChatMessageOps.withOptimisticReaction(
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
    await refreshReactions();
  }

  Future<void> refreshReactions() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    final ids = ChatMessageOps.ackedIds(state.messages);
    if (ids.isEmpty) return;

    final response = await _repo.listReactions(messageIds: ids);
    if (!response.success || state.openPeerId != peerId) return;
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
