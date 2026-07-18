/// Presentation-side view of one decrypted chat message — what the chat UI
/// kit renders. Chat cubits (channel chat, server DMs, central DMs) map their
/// storage/crypto models into this; the kit never touches envelopes or keys.
class ChatMessage {
  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime sentAt;
  final bool isMine;

  /// Sent optimistically, not yet acknowledged by the server.
  final bool isPending;

  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.sentAt,
    required this.isMine,
    this.isPending = false,
  });
}
