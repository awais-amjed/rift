part of 'central_dm_cubit.dart';

/// Turning central-DM envelope rows into rendered messages.
///
/// Sender verification keys come from the directory (TOFU): the peer's
/// `signing_public_key` for their rows, ours for ours. A row that fails to
/// verify is dropped, never rendered.
mixin _CentralDmDecryptMixin on Cubit<CentralDmState> {
  CryptoRepository get _crypto;
  String? get _myUserId;
  Map<String, String> get _peerSigningKeys;
  Map<String, String> get _peerChatKeys;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);
  Future<ServerIdentity> _signingIdentity();

  /// The DM context both sides derive independently. The rule is
  /// [MessageEnvelope.conversationContext]'s — server DMs and the push isolate
  /// derive the same string, and a second spelling of it would be a
  /// conversation that silently fails to verify.
  static String _context(String a, String b) =>
      MessageEnvelope.conversationContext(a, b);

  Future<List<ChatMessage>> _decryptRows(
    String peerId,
    List<Map<String, dynamic>> rows,
  ) async {
    final result = <ChatMessage>[];
    for (final row in rows) {
      final message = await _decryptRow(
        row,
        peerId: peerId,
        peerHandle: state.openPeerHandle ?? 'unknown',
      );
      if (message != null) result.add(message);
    }
    return result;
  }

  /// Decrypt + verify one row. Returns null on any failure — a message that
  /// doesn't verify is never rendered.
  Future<ChatMessage?> _decryptRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerHandle,
  }) async {
    final myId = _myUserId;
    if (myId == null) return null;

    final key = await _dmKeyFor(peerId, _peerChatKeys[peerId]);
    if (key == null) return null;

    final senderId = row['sender_id'] as String;
    final isMine = senderId == myId;

    try {
      final Uint8List senderKey;
      if (isMine) {
        senderKey = (await _signingIdentity()).publicKeyBytes;
      } else {
        final signingKeyB64 = _peerSigningKeys[peerId];
        if (signingKeyB64 == null) return null;
        senderKey = CryptoRepository.fromBase64(signingKeyB64);
      }

      final plaintext = await _crypto.openMessage(
        envelope: MessageEnvelope.fromJson(row),
        messageKey: key,
        senderPublicKey: senderKey,
        contextId: _context(myId, peerId),
      );
      if (plaintext == null) return null;

      final body = MessageBody.decode(plaintext);
      return ChatMessage(
        id: '${row['id']}',
        authorId: senderId,
        authorName: isMine ? (state.myHandle ?? 'me') : peerHandle,
        text: body.text,
        attachments: body.attachments,
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: isMine,
        editedAt: DateTime.tryParse('${row['edited_at']}'),
      );
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] dropped ${row['id']}: $e');
      return null;
    }
  }
}
