part of 'dm_cubit.dart';

/// Pins in the open server DM. Either side may pin; nothing to hold.
///
/// Same shape as a channel's (`_ChannelChatPinsMixin`): the list is read when
/// it is opened rather than held, and a pin is drawn on its row only once the
/// server has taken it.
mixin _DmPinsMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;

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
    final response = await _serverCubit.listDmPins(peerId: peerId);
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

    final response = await _serverCubit.setPinned(
      scope: 'dm',
      messageId: id,
      pinned: pinned,
    );
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

  /// A pin moved in one of our conversations. Re-read the row if it is the
  /// open one; the ring names the pair, sorted.
  void _onPinDoorbell(Map<String, dynamic> payload) {
    if (isClosed) return;
    final peerId = state.openPeerId;
    final pair = {
      BroadcastPayload.stringOf(payload, 'user_low'),
      BroadcastPayload.stringOf(payload, 'user_high'),
    };
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (peerId == null || messageId == null || !pair.contains(peerId)) return;
    unawaited(refreshMessage(messageId));
  }
}
