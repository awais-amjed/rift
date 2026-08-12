part of 'channel_chat_cubit.dart';

/// Editing and deleting messages already in a channel.
///
/// An edit re-seals the whole body — the new text plus the message's existing
/// attachments — at the *current* key version, because a rotation may have
/// happened since the original send. The server overwrites the envelope in
/// place and stamps `edited_at`; it still never sees plaintext.
mixin _ChannelChatEditMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  int get _currentKeyVersion;
  void _ringChangeDoorbell(String messageId);

  /// Re-seal [messageId] with [newText]. Attachments are carried over
  /// unchanged. No-ops when the text is unchanged or empty.
  Future<void> editMessage(String messageId, String newText) async {
    final channelId = state.channelId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    final key = _keys[_currentKeyVersion];
    final id = int.tryParse(messageId);
    if (channelId == null || server == null || user == null || key == null) {
      return;
    }
    if (id == null) return; // a pending message has no server id yet

    final trimmed = newText.trim();
    final existing = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (existing == null) return;
    if (trimmed.isEmpty || trimmed == existing.text) return;

    try {
      final host = Uri.parse(server.supabaseUrl).host;
      final identity = await _vaultCubit.getIdentityForHost(
        host,
        serverId: server.id,
        version: server.keyVersion,
      );
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(
          text: trimmed,
          attachments: existing.attachments,
        ).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: channelId,
        keyVersion: _currentKeyVersion,
      );

      final response = await _serverCubit.editChatMessage(
        channelId: channelId,
        messageId: id,
        envelope: envelope.toJson(),
      );
      if (state.channelId != channelId) return;

      if (!response.success) {
        HelperMethods.showError(
          error: response.error ?? 'Failed to edit message',
        );
        return;
      }

      final data = response.data as Map<String, dynamic>;
      emit(
        state.copyWith(
          messages: ChatMessageOps.applyEdit(
            state.messages,
            messageId: messageId,
            text: trimmed,
            editedAt:
                DateTime.tryParse('${data['edited_at']}') ?? DateTime.now(),
          ),
        ),
      );
      _ringChangeDoorbell(messageId);
    } catch (e) {
      HelperMethods.printDebug('[Chat] edit failed: $e');
      if (state.channelId == channelId) {
        HelperMethods.showError(error: 'Failed to edit message');
      }
    }
  }

  /// Hard-delete [messageId]. The row is removed locally straight away; the
  /// server enforces who may do it.
  Future<void> deleteMessage(String messageId) async {
    final channelId = state.channelId;
    final id = int.tryParse(messageId);
    if (channelId == null || id == null) return;

    try {
      final response = await _serverCubit.deleteChatMessage(
        channelId: channelId,
        messageId: id,
      );
      if (state.channelId != channelId) return;

      if (!response.success) {
        HelperMethods.showError(
          error: response.error ?? 'Failed to delete message',
        );
        return;
      }

      emit(
        state.copyWith(
          messages: ChatMessageOps.removeMessage(state.messages, messageId),
        ),
      );
      _ringChangeDoorbell(messageId);
    } catch (e) {
      HelperMethods.printDebug('[Chat] delete failed: $e');
      if (state.channelId == channelId) {
        HelperMethods.showError(error: 'Failed to delete message');
      }
    }
  }
}
