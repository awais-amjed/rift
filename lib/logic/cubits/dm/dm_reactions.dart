part of 'dm_cubit.dart';

/// Reactions on server DMs. Not E2E — the server sees who reacted with what
/// (ARCHITECTURE.md §4).
mixin _DmReactionsMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  void _ringReactionDoorbell();

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

    final response = await _serverCubit.toggleReaction(
      scope: 'dm',
      peerId: peerId,
      messageId: idNum,
      emoji: emoji,
    );
    if (state.openPeerId != peerId) return;
    if (response.success) {
      _ringReactionDoorbell();
    } else {
      HelperMethods.showError(error: 'Failed to react');
    }
    await refreshReactions();
  }

  Future<void> refreshReactions() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    final ids = ChatMessageOps.ackedIds(state.messages);
    if (ids.isEmpty) return;

    final response = await _serverCubit.listReactions(
      scope: 'dm',
      peerId: peerId,
      messageIds: ids,
    );
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
