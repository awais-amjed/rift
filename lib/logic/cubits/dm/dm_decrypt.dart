part of 'dm_cubit.dart';

/// Turning server-DM envelope rows into rendered messages.
///
/// Verification is the point: the sender's attested key opens the envelope and
/// checks the signature, and anything that fails is dropped rather than shown.
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
  /// sender key when present, else [peerSigningKey]. Returns null on any
  /// failure — never rendered.
  Future<ChatMessage?> _decryptDmRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerName,
    required String? peerChatKey,
    required String? peerSigningKey,
  }) async {
    final localUserId = _localUserId;
    if (localUserId == null) return null;

    final key = await _dmKeyFor(peerId, peerChatKey);
    if (key == null) return null;

    final senderId = row['sender_id'] as String;
    final isMine = senderId == localUserId;
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

      final plaintext = await _crypto.openMessage(
        envelope: MessageEnvelope.fromJson(row),
        messageKey: key,
        senderPublicKey: senderKey,
        contextId: DmCubit.conversationContext(localUserId, peerId),
      );
      if (plaintext == null) return null;

      final body = MessageBody.decode(plaintext);
      return ChatMessage(
        id: '${row['id']}',
        authorId: senderId,
        authorName: isMine
            ? (_serverCubit.state.selectedServer?.user?.displayName ?? 'Me')
            : (row['sender_name'] as String? ?? peerName),
        authorAvatarPath: row['sender_avatar_path'] as String?,
        text: body.text,
        attachments: body.attachments,
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: isMine,
        editedAt: DateTime.tryParse('${row['edited_at']}'),
        reactions: ReactionOps.fromRow(row),
      );
    } catch (e) {
      HelperMethods.printDebug('[DM] dropped message ${row['id']}: $e');
      return null;
    }
  }
}
