part of 'dm_cubit.dart';

/// Editing and deleting messages in a server DM.
///
/// Same shape as the channel path: an edit re-seals the whole body (new text +
/// the message's existing attachments) and the server overwrites the envelope
/// in place. DM key_version is always 1 — DMs don't rotate.
mixin _DmEditMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  Future<ServerIdentity> _vaultIdentityFor(Server server);

  /// Tell the peer that this message changed, so their open conversation
  /// re-reads it. Implemented by the hub.

  /// Re-seal [messageId] with [newText]; attachments carry over unchanged.
  Future<void> editMessage(String messageId, String newText) async {
    final peerId = state.openPeerId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    final id = int.tryParse(messageId);
    if (peerId == null || server == null || user == null || id == null) return;
    final key = _dmKeys[peerId];
    if (key == null) return;

    final trimmed = newText.trim();
    final existing = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (existing == null) return;
    if (trimmed.isEmpty || trimmed == existing.text) return;

    try {
      final identity = await _vaultIdentityFor(server);
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody.edited(existing, trimmed).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: DmCubit.conversationContext(user.id, peerId),
        keyVersion: 1,
      );

      final response = await _serverCubit.editDm(
        messageId: id,
        envelope: envelope.toJson(),
      );
      if (state.openPeerId != peerId) return;

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
    } catch (e) {
      HelperMethods.printDebug('[DM] edit failed: $e');
      if (state.openPeerId == peerId) {
        HelperMethods.showError(error: 'Failed to edit message');
      }
    }
  }

  /// Hard-delete [messageId]. There is one row per DM, so this removes it for
  /// the peer too — see `delete_dm`.
  Future<void> deleteMessage(String messageId) async {
    final peerId = state.openPeerId;
    final id = int.tryParse(messageId);
    if (peerId == null || id == null) return;

    // Captured before the row goes: once it leaves the list, nothing else in
    // the app knows which blobs were its.
    final doomed = state.messages.where((m) => m.id == messageId).firstOrNull;

    try {
      final response = await _serverCubit.deleteDm(messageId: id);
      if (state.openPeerId != peerId) return;

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
      unawaited(
        AttachmentCleanup.forMessage(
          doomed,
          delete: _serverCubit.deleteAttachments,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('[DM] delete failed: $e');
      if (state.openPeerId == peerId) {
        HelperMethods.showError(error: 'Failed to delete message');
      }
    }
  }
}
