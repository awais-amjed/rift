part of 'channel_chat_cubit.dart';

/// Pinning in the open channel, and reading its pins back.
///
/// Not E2E — the server sees *which* messages are pinned, never what they say
/// (ARCHITECTURE.md §4). The pinned list is not held in state: it is read
/// when somebody opens it, decrypted by the same code as a page of history,
/// and a pin that moves while it is closed costs nothing.
mixin _ChannelChatPinsMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;

  Future<List<ChatMessage>> _decryptRows(
    String channelId,
    List<Map<String, dynamic>> rows,
  );

  Future<void> refreshMessage(String messageId);

  /// The open channel's pinned messages, newest pin first, or null when they
  /// could not be read.
  Future<List<ChatMessage>?> loadPins() async {
    final channelId = state.channelId;
    if (channelId == null) return null;
    final response = await _serverCubit.listChannelPins(channelId: channelId);
    if (!response.success || state.channelId != channelId) return null;
    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .cast<Map<String, dynamic>>();
    return _decryptRows(channelId, rows);
  }

  /// Pin or unpin [message]. Answers whether the server took it.
  ///
  /// Applied to the row only once the server has said yes: a pin is a thing
  /// the whole channel sees, and one drawn before it is true is a claim about
  /// what everybody else is looking at.
  Future<bool> setPinned(ChatMessage message, {required bool pinned}) async {
    final channelId = state.channelId;
    final id = int.tryParse(message.id);
    if (channelId == null || id == null) return false;

    final response = await _serverCubit.setPinned(
      scope: 'channel',
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
    if (state.channelId != channelId) return true;
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

  /// Somebody pinned or unpinned a message here. The row is re-read rather
  /// than trusted from the ring: the ring says where to look, not what is
  /// true.
  void _onPinDoorbell(Map<String, dynamic> payload) {
    if (isClosed) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (messageId != null) unawaited(refreshMessage(messageId));
  }
}
