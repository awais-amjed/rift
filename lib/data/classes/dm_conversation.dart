import 'chat_message.dart';

/// One DM conversation as shown in the Home list: the peer's identity
/// material plus the decrypted latest message (null when it can't be
/// decrypted, e.g. the peer rotated identities).
class DmConversation {
  final String peerId;
  final String peerName;

  /// Peer's X25519 chat key (base64) — derives the DM key. Null if the peer
  /// hasn't published one (conversation exists but can't continue).
  final String? peerChatPublicKey;

  /// Peer's Ed25519 key (base64) — verifies their message signatures.
  final String? peerSigningPublicKey;

  final ChatMessage? lastMessage;

  const DmConversation({
    required this.peerId,
    required this.peerName,
    this.peerChatPublicKey,
    this.peerSigningPublicKey,
    this.lastMessage,
  });
}
