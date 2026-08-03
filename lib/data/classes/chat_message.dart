import 'attachment.dart';
import 'message_reaction.dart';

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

  /// Aggregated emoji reactions (NOT E2E — server-visible). Merged in
  /// separately from the message body via `list_reactions`.
  final List<MessageReaction> reactions;

  final DateTime sentAt;
  final bool isMine;

  /// Sent optimistically, not yet acknowledged by the server.
  final bool isPending;

  /// When the author last edited this message, or null if never edited.
  /// Drives the "(edited)" marker.
  final DateTime? editedAt;

  bool get isEdited => editedAt != null;

  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.sentAt,
    required this.isMine,
    this.attachments = const [],
    this.reactions = const [],
    this.isPending = false,
    this.editedAt,
  });

  ChatMessage copyWith({
    List<MessageReaction>? reactions,
    String? text,
    DateTime? editedAt,
  }) => ChatMessage(
    id: id,
    authorId: authorId,
    authorName: authorName,
    text: text ?? this.text,
    sentAt: sentAt,
    isMine: isMine,
    attachments: attachments,
    reactions: reactions ?? this.reactions,
    isPending: isPending,
    editedAt: editedAt ?? this.editedAt,
  );
}
