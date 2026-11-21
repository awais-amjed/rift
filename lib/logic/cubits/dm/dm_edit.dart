part of 'dm_cubit.dart';

/// Editing and deleting messages in a server DM.
///
/// Same shape as the channel path: an edit re-seals the whole body (new text +
/// the message's existing attachments) and the server overwrites the envelope
/// in place. DM key_version is always 1 — DMs don't rotate.
mixin _DmEditMixin on Cubit<DmState> {
  Server? get _server;
  DmsApi get _dms;
  AttachmentsApi get _attachments;
  SavedConversation get _saved;
  CryptoRepository get _crypto;
  Map<String, Uint8List> get _dmKeys;
  Future<ServerIdentity> _vaultIdentityFor(Server server);

  /// Implemented by the history and conversations mixins: after an edit or
  /// delete, the saved copy and the list's preview are brought up to date.
  /// Neither was, so the next open drew the old text for a moment, and a
  /// deleted last message stayed in the list until something else moved it.
  Future<void> refreshMessage(String messageId);
  Future<void> refreshConversations();

  /// Re-seal [messageId] with [newText]; attachments carry over unchanged.
  Future<void> editMessage(String messageId, String newText) async {
    final peerId = state.openPeerId;
    final server = _server;
    final user = server?.user;
    final id = int.tryParse(messageId);
    if (peerId == null || server == null || user == null || id == null) return;
    final key = _dmKeys[peerId];
    if (key == null) return;

    final trimmed = newText.trim();
    final existing = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (existing == null) return;
    if (trimmed.isEmpty || trimmed == existing.text) return;
    // This server's, taken before the awaits: read after them, a switch in
    // between sent the envelope sealed here to a row on the next server.
    final dms = _dms;

    try {
      final identity = await _vaultIdentityFor(server);
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody.edited(existing, trimmed).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: DmCubit.conversationContext(user.id, peerId),
        keyVersion: 1,
      );

      final response = await dms.editDm(
        messageId: id,
        envelope: envelope.toJson(),
      );
      if (state.openPeerId != peerId) return;

      if (!response.success) {
        emit(
          state.copyWith(
            notice: Notice.error(
              EditRefusal.describe(
                    response.errorCode,
                    timedOut: user.isTimedOut,
                    peerName: state.openPeerName ?? 'This person',
                  ) ??
                  response.error ??
                  'Failed to edit message',
            ),
          ),
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
      unawaited(refreshMessage(messageId));
      unawaited(refreshConversations());
    } catch (e) {
      HelperMethods.printDebug('[DM] edit failed: $e');
      if (state.openPeerId == peerId) {
        emit(state.copyWith(notice: Notice.error('Failed to edit message')));
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
    // And the server it is on, before the await.
    final attachments = _attachments;

    try {
      final response = await _dms.deleteDm(messageId: id);
      if (state.openPeerId != peerId) return;

      if (!response.success) {
        emit(
          state.copyWith(
            notice: Notice.error(response.error ?? 'Failed to delete message'),
          ),
        );
        return;
      }

      _saved.remove(messageId);
      emit(
        state.copyWith(
          messages: ChatMessageOps.removeMessage(state.messages, messageId),
        ),
      );
      unawaited(
        AttachmentCleanup.forMessage(
          doomed,
          origin: attachments.origin,
          delete: attachments.deleteAttachments,
        ),
      );
      unawaited(refreshConversations());
    } catch (e) {
      HelperMethods.printDebug('[DM] delete failed: $e');
      if (state.openPeerId == peerId) {
        emit(state.copyWith(notice: Notice.error('Failed to delete message')));
      }
    }
  }
}
