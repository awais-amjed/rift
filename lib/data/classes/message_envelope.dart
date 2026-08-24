/// The E2E-encrypted wire format of a chat message — the only message shape
/// any server ever stores (ARCHITECTURE.md §4). Identical across group
/// channels, server DMs, and central DMs; only the key source differs.
class MessageEnvelope {
  /// AES-256-GCM ciphertext + auth tag, base64.
  final String ciphertext;

  /// AES-GCM nonce, base64.
  final String nonce;

  /// Ed25519 signature by the sender over [signedPayload], base64.
  final String signature;

  /// Which key version encrypted this message (1 for DMs — no rotation;
  /// increments on channel-key rotation).
  final int keyVersion;

  const MessageEnvelope({
    required this.ciphertext,
    required this.nonce,
    required this.signature,
    required this.keyVersion,
  });

  factory MessageEnvelope.fromJson(Map<String, dynamic> json) {
    return MessageEnvelope(
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
      signature: json['signature'] as String,
      keyVersion: json['key_version'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'nonce': nonce,
    'signature': signature,
    'key_version': keyVersion,
  };

  /// Canonical string the sender signs and receivers verify. Binds the
  /// ciphertext to its context (channel/conversation id) and key version so a
  /// message can't be replayed into another channel or under another key.
  static String signedPayload({
    required String contextId,
    required int keyVersion,
    required String nonce,
    required String ciphertext,
  }) => 'chatmsg:v1:$contextId:$keyVersion:$nonce:$ciphertext';

  /// The signed context for a one-to-one conversation.
  ///
  /// Order-independent, so both parties derive the same id without agreeing on
  /// anything first — and so an envelope cannot be replayed into a different
  /// conversation. It lives here rather than in a cubit because three places
  /// derive it (server DMs, central DMs, and the push isolate that opens both
  /// while the app is asleep), and a fourth spelling of it would be a
  /// conversation that silently fails to verify.
  static String conversationContext(String userA, String userB) {
    final ids = [userA, userB]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }
}
