part of 'central_dm_cubit.dart';

/// Turning central-DM envelope rows into rendered messages.
///
/// Sender verification keys come from the directory (TOFU): the peer's
/// `signing_public_key` for their rows, ours for ours. A row that fails to
/// verify is dropped, never rendered; one that verifies but does not open
/// under this device's DM key is locked — see [openSealed].
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

  /// Decrypt + verify one row. Null for a message that doesn't verify — never
  /// rendered — and a locked row for one this device holds no working key for.
  Future<ChatMessage?> _decryptRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerHandle,
  }) async {
    final myId = _myUserId;
    if (myId == null) return null;

    final senderId = row['sender_id'] as String;
    final isMine = senderId == myId;
    final authorName = isMine ? (state.myHandle ?? 'me') : peerHandle;

    // No DM key at all: the message waits, like a channel's without one.
    final key = await _dmKeyFor(peerId, _peerChatKeys[peerId]);
    if (key == null) return _lockedRow(row, authorName, isMine: isMine);

    try {
      final Uint8List senderKey;
      if (isMine) {
        senderKey = (await _signingIdentity()).publicKeyBytes;
      } else {
        final signingKeyB64 = _peerSigningKeys[peerId];
        if (signingKeyB64 == null) return null;
        senderKey = CryptoRepository.fromBase64(signingKeyB64);
      }

      final opened = await openSealed(
        _crypto,
        envelope: MessageEnvelope.fromJson(row),
        messageKey: key,
        senderPublicKey: senderKey,
        contextId: _context(myId, peerId),
      );
      switch (opened.outcome) {
        case SealedOutcome.dropped:
          return null;
        case SealedOutcome.locked:
          return _lockedRow(row, authorName, isMine: isMine);
        case SealedOutcome.opened:
      }

      final body = MessageBody.decode(opened.plaintext!);
      return ChatMessage(
        id: '${row['id']}',
        authorId: senderId,
        authorName: authorName,
        text: body.text,
        attachments: body.attachments,
        preview: body.preview,
        replyToId: body.replyToId,
        forwarded: body.forwarded,
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: isMine,
        editedAt: DateTime.tryParse('${row['edited_at']}'),
        pinnedAt: PinOps.pinnedAtOf(row),
      );
    } catch (e) {
      HelperMethods.printDebug('[CentralDM] dropped ${row['id']}: $e');
      return null;
    }
  }

  /// A message this device can see but not open. See [ChatMessage.isLocked].
  ChatMessage _lockedRow(
    Map<String, dynamic> row,
    String authorName, {
    required bool isMine,
  }) => ChatMessage(
    id: '${row['id']}',
    authorId: row['sender_id'] as String,
    authorName: authorName,
    text: '',
    sentAt: DateTime.parse(row['created_at'] as String),
    isMine: isMine,
    editedAt: DateTime.tryParse('${row['edited_at']}'),
    isLocked: true,
    pinnedAt: PinOps.pinnedAtOf(row),
  );
}
