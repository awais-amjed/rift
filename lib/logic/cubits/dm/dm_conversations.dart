part of 'dm_cubit.dart';

/// The list of conversations with their decrypted previews.
mixin _DmConversationsMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;

  /// Fire OS notifications for newly-arrived messages across all conversations.
  void _notifyFromConversations(List<DmConversation> conversations);
  Future<ChatMessage?> _decryptDmRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerName,
    required String? peerChatKey,
    required String? peerSigningKey,
  });

  String? get _localUserId => _serverCubit.state.selectedServer?.user?.id;

  Future<void> refreshConversations() async {
    final localUserId = _localUserId;
    if (localUserId == null) return;
    emit(state.copyWith(conversationsLoading: true));

    final response = await _serverCubit.listDmConversations();
    if (isClosed) return;
    if (!response.success) {
      emit(state.copyWith(conversationsLoading: false));
      return;
    }

    final rows =
        ((response.data as Map<String, dynamic>)['conversations'] as List)
            .cast<Map<String, dynamic>>();

    final conversations = <DmConversation>[];
    for (final row in rows) {
      final peerId = row['peer_id'] as String;
      final peerName = row['peer_name'] as String? ?? 'Unknown';
      final peerChatKey = row['peer_chat_public_key'] as String?;
      final peerSigningKey = row['peer_public_key'] as String?;

      ChatMessage? preview;
      final last = row['last_message'] as Map<String, dynamic>?;
      if (last != null) {
        preview = await _decryptDmRow(
          last,
          peerId: peerId,
          peerName: peerName,
          peerChatKey: peerChatKey,
          peerSigningKey: peerSigningKey,
        );
      }
      conversations.add(
        DmConversation(
          peerId: peerId,
          peerName: peerName,
          peerChatPublicKey: peerChatKey,
          peerSigningPublicKey: peerSigningKey,
          lastMessage: preview,
        ),
      );
    }

    emit(
      state.copyWith(conversations: conversations, conversationsLoading: false),
    );
    _notifyFromConversations(conversations);
  }
}
