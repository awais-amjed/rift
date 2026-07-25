import 'attachment.dart';

/// One decrypted, signature-verified chat message — what cubits hold in state
/// and the chat UI kit renders. Envelopes that fail verification never become
/// a ChatMessage.
class ChatMessage {
  final String id;
  final String authorId;
  final String authorName;
  final String text;

  /// Decrypted attachments carried in the message body (images, audio, files).
  /// Empty for a plain text message.
  final List<Attachment> attachments;

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
    this.attachments = const [],
    this.isPending = false,
  });
}
