part of 'dm_cubit.dart';

/// Turning server-DM envelope rows into rendered messages.
///
/// Verification is the point: the sender's attested key checks the signature,
/// and a row that fails it is dropped rather than shown. A row that verifies
/// but does not open under this device's DM key is *locked* — see
/// [openSealed] — which is what a conversation looks like the moment the
/// other person's key changes.
/// A conversation preview goes through the same path as the open conversation
/// ([_DmConversationsMixin] calls [_decryptDmRow] directly), so there is no
/// second, laxer way for a row to reach the screen.
mixin _DmDecryptMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);
  Future<ServerIdentity> _vaultIdentityFor(Server server);
  String? get _localUserId;

  Future<List<ChatMessage>> _decryptRows(
    String peerId,
    List<Map<String, dynamic>> rows,
  ) async {
    final result = <ChatMessage>[];
    for (final row in rows) {
      final message = await _decryptDmRow(
        row,
        peerId: peerId,
        peerName: state.openPeerName ?? 'Unknown',
        peerChatKey: null, // key is already cached from openConversation
        peerSigningKey: null, // per-row attested key is used instead
      );
      if (message != null) result.add(message);
    }
    return result;
  }

  /// Decrypt + verify one DM row. Verification uses the row's server-attested
  /// sender key when present, else [peerSigningKey]. Null for a row that
  /// fails verification — never rendered — and a locked row for one this
  /// device holds no working key for.
  Future<ChatMessage?> _decryptDmRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerName,
    required String? peerChatKey,
    required String? peerSigningKey,
  }) async {
    final localUserId = _localUserId;
    if (localUserId == null) return null;

    final senderId = row['sender_id'] as String;
    final isMine = senderId == localUserId;
    final authorName = isMine
        ? (_serverCubit.state.selectedServer?.user?.displayName ?? 'Me')
        : (row['sender_name'] as String? ?? peerName);

    // No DM key at all — their key is not published, or not yet fetched.
    // Nothing is wrong with the message; it waits, like a channel's.
    final key = await _dmKeyFor(peerId, peerChatKey);
    if (key == null) return _lockedDmRow(row, authorName, isMine: isMine);
    final senderKeyB64 =
        row['sender_public_key'] as String? ?? (isMine ? null : peerSigningKey);
    if (senderKeyB64 == null && !isMine) return null;

    try {
      // For rows lacking an attested sender key (conversation previews of our
      // own messages), fall back to our own signing key.
      final Uint8List senderKey;
      if (senderKeyB64 != null) {
        senderKey = CryptoRepository.fromBase64(senderKeyB64);
      } else {
        final server = _serverCubit.state.selectedServer!;
        final identity = await _vaultIdentityFor(server);
        senderKey = identity.publicKeyBytes;
      }

      final opened = await openSealed(
        _crypto,
        envelope: MessageEnvelope.fromJson(row),
        messageKey: key,
        senderPublicKey: senderKey,
        contextId: DmCubit.conversationContext(localUserId, peerId),
      );
      switch (opened.outcome) {
        case SealedOutcome.dropped:
          return null;
        case SealedOutcome.locked:
          return _lockedDmRow(row, authorName, isMine: isMine);
        case SealedOutcome.opened:
      }

      final body = MessageBody.decode(opened.plaintext!);
      return ChatMessage(
        id: '${row['id']}',
        authorId: senderId,
        authorName: authorName,
        authorAvatarPath: row['sender_avatar_path'] as String?,
        text: body.text,
        attachments: body.attachments,
        preview: body.preview,
        replyToId: body.replyToId,
        forwarded: body.forwarded,
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: isMine,
        editedAt: DateTime.tryParse('${row['edited_at']}'),
        reactions: ReactionOps.fromRow(row),
        pinnedAt: PinOps.pinnedAtOf(row),
      );
    } catch (e) {
      HelperMethods.printDebug('[DM] dropped message ${row['id']}: $e');
      return null;
    }
  }

  /// A message this device can see but not open — its author and time only,
  /// which the server stores in the clear anyway. See [ChatMessage.isLocked].
  ChatMessage _lockedDmRow(
    Map<String, dynamic> row,
    String authorName, {
    required bool isMine,
  }) => ChatMessage(
    id: '${row['id']}',
    authorId: row['sender_id'] as String,
    authorName: authorName,
    authorAvatarPath: row['sender_avatar_path'] as String?,
    text: '',
    sentAt: DateTime.parse(row['created_at'] as String),
    isMine: isMine,
    editedAt: DateTime.tryParse('${row['edited_at']}'),
    isLocked: true,
    pinnedAt: PinOps.pinnedAtOf(row),
  );
}
