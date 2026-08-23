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

  /// One row of the central directory (`users` on the central tier).
  ///
  /// Lives here rather than in the cubit that calls it because the column
  /// names are the thing worth pinning down: the August rewrite renamed
  /// central's `user_id` to `id`, the repository followed and this mapping did
  /// not, so every handle search threw on the cast and the drop-down sat on
  /// "Searching…" forever. A row shape with no test is a rename away from
  /// doing that again.
  factory DmConversation.fromDirectoryRow(Map<String, dynamic> row) {
    return DmConversation(
      peerId: row['id'] as String,
      peerName: row['handle'] as String,
      peerChatPublicKey: row['chat_public_key'] as String?,
      peerSigningPublicKey: row['signing_public_key'] as String?,
    );
  }
}
