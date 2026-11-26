part of 'dm_cubit.dart';

/// Reactions on server DMs. Not E2E — the server sees who reacted with what
/// (ARCHITECTURE.md §4).
///
/// A message page arrives with its reactions already on it, so nothing here
/// runs on open or on scroll — only when a reaction changes afterwards.
mixin _DmReactionsMixin on Cubit<DmState> {
  ReactionsApi get _reactions;

  /// Our own toggles whose ring is still to come.
  final ReactionEchoes _echoes = ReactionEchoes();

  /// Whether a reaction ring about [messageId] is the echo of our own toggle,
  /// whose counts are already on screen.
  bool _isOwnEcho(Map<String, dynamic> payload, String messageId) {
    final from = BroadcastPayload.stringOf(payload, 'user_id');
    return from != null &&
        from == _reactions.callerId &&
        _echoes.take(messageId);
  }

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

    final response = await _reactions.toggleReaction(
      scope: 'dm',
      messageId: idNum,
      emoji: emoji,
    );
    if (state.openPeerId != peerId) return;
    if (!response.success) {
      emit(
        state.copyWith(notice: Notice.error(ReactionsApi.failureOf(response))),
      );
    }
    // The counts came back with it, so its own ring need not ask again.
    final counts = ReactionsApi.countsOf(response, idNum);
    if (counts != null) {
      _echoes.expect(messageId);
      emit(
        state.copyWith(
          messages: ReactionOps.withReactionsFor(
            state.messages,
            messageId: messageId,
            data: counts,
          ),
        ),
      );
      return;
    }
    final read = await refreshReactionsFor(messageId);
    // Neither got through — offline, most likely — so nothing replaced the
    // flip: take it back, or the chip says a reaction is there that is not.
    if (!response.success && !read && state.openPeerId == peerId) {
      emit(
        state.copyWith(
          messages: ReactionOps.withOptimisticReaction(
            state.messages,
            messageId: messageId,
            emoji: emoji,
          ),
        ),
      );
    }
  }

  /// Re-fetch one message's authoritative reactions, leaving the rest alone.
  ///
  /// Answers whether the counts were read.
  Future<bool> refreshReactionsFor(String messageId) async {
    final peerId = state.openPeerId;
    final idNum = int.tryParse(messageId);
    if (peerId == null || idNum == null) return false;

    final response = await _reactions.listReactions(
      scope: 'dm',
      messageIds: [idNum],
    );
    if (!response.success || state.openPeerId != peerId) return false;
    emit(
      state.copyWith(
        messages: ReactionOps.withReactionsFor(
          state.messages,
          messageId: messageId,
          data: response.data as Map<String, dynamic>,
        ),
      ),
    );
    return true;
  }

  /// Every loaded message — the fallback for a doorbell that didn't name one.
  Future<void> refreshReactions() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    final ids = ChatMessageOps.ackedIds(state.messages);
    if (ids.isEmpty) return;

    final response = await _reactions.listReactions(
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
