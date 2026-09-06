part of 'central_dm_cubit.dart';

/// Editing and deleting central DMs.
///
/// Unlike sending, these go straight to the table rather than through the
/// quota-enforcing RPC — an edit is not a new message, so it must not spend
/// quota, and a delete obviously doesn't either.
mixin _CentralDmEditMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  String? get _myUserId;
  Future<ServerIdentity> _signingIdentity();

  /// Re-seal [messageId] with [newText]; attachments carry over unchanged.
  Future<void> editMessage(String messageId, String newText) async {
    final peerId = state.openPeerId;
    final myId = _myUserId;
    final id = int.tryParse(messageId);
    if (peerId == null || myId == null || id == null) return;
    final key = _dmKeys[peerId];
    if (key == null) return;

    final trimmed = newText.trim();
    final existing = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (existing == null) return;
    if (trimmed.isEmpty || trimmed == existing.text) return;

    try {
      final identity = await _signingIdentity();
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(
          text: trimmed,
          attachments: existing.attachments,
          preview: existing.preview,
        ).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: _CentralDmDecryptMixin._context(myId, peerId),
        keyVersion: 1,
      );

      final response = await _repo.editDm(
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
      HelperMethods.printDebug('[CentralDM] edit failed: $e');
      if (state.openPeerId == peerId) {
        HelperMethods.showError(error: 'Failed to edit message');
      }
    }
  }

  /// Hard-delete [messageId] — removes it for the peer too.
  Future<void> deleteMessage(String messageId) async {
    final peerId = state.openPeerId;
    final id = int.tryParse(messageId);
    if (peerId == null || id == null) return;

    // Captured before the row goes: once it leaves the list, nothing else in
    // the app knows which blobs were its.
    final doomed = state.messages.where((m) => m.id == messageId).firstOrNull;

    try {
      final response = await _repo.deleteDm(messageId: id);
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
        AttachmentCleanup.forMessage(doomed, delete: _repo.deleteAttachments),
      );
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] delete failed: $e');
      if (state.openPeerId == peerId) {
        HelperMethods.showError(error: 'Failed to delete message');
      }
    }
  }
}
