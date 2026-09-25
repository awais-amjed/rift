part of 'central_dm_cubit.dart';

/// Pins in the open central DM. Either side may pin, fifty to a conversation,
/// and a pin goes when its message does — a central message still expires at
/// thirty days, pinned or not.
///
/// Same shape as a server DM's (`_DmPinsMixin`).
mixin _CentralDmPinsMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;

  Future<List<ChatMessage>> _decryptRows(
    String peerId,
    List<Map<String, dynamic>> rows,
  );

  Future<void> refreshMessage(String messageId);

  /// The open conversation's pinned messages, newest pin first, or null when
  /// they could not be read.
  Future<List<ChatMessage>?> loadPins() async {
    final peerId = state.openPeerId;
    if (peerId == null) return null;
    final response = await _repo.listPins(peerId: peerId);
    if (!response.success || state.openPeerId != peerId) return null;
    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .cast<Map<String, dynamic>>();
    return _decryptRows(peerId, rows);
  }

  /// Pin or unpin [message]. Answers whether the server took it.
  Future<bool> setPinned(ChatMessage message, {required bool pinned}) async {
    final peerId = state.openPeerId;
    final id = int.tryParse(message.id);
    if (peerId == null || id == null) return false;

    final response = await _repo.setPinned(messageId: id, pinned: pinned);
    if (!response.success) {
      HelperMethods.showError(
        error:
            PinOps.errorFor(response.error) ??
            (pinned ? 'Could not pin the message' : 'Could not unpin it'),
      );
      return false;
    }
    if (state.openPeerId != peerId) return true;
    emit(
      state.copyWith(
        messages: PinOps.withPin(
          state.messages,
          id: message.id,
          pinnedAt: pinned ? DateTime.now() : null,
        ),
      ),
    );
    return true;
  }

  /// A pin moved in the conversation with [peerId]. Re-read that one row if
  /// the conversation is open; the ring says where to look, not what is true.
  void _onPinChanged(String peerId, String messageId) {
    if (isClosed || state.openPeerId != peerId) return;
    unawaited(refreshMessage(messageId));
  }
}
