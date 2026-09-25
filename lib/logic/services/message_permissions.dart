import '../../data/classes/chat_message.dart';

/// Who may edit or delete a message. Pure so the rules are stated once and
/// tested, rather than re-derived at each context menu.
///
/// The server enforces the same rules (`edit_message` / `delete_message`);
/// this only decides which menu entries to offer.
class MessagePermissions {
  const MessagePermissions._();

  /// Only the author may edit, and only a message that has text.
  ///
  /// A moderator can *delete* someone's message but never rewrite it — putting
  /// words in someone's mouth under their own name is worse than removing the
  /// message. Attachment-only messages aren't editable: there is no text to
  /// change, and swapping attachments would mean a fresh upload.
  static bool canEdit(ChatMessage message) =>
      message.isMine && !message.isPending && message.text.isNotEmpty;

  /// The author always may; a moderator may delete anyone's.
  ///
  /// [isModerator] is false for DMs — a conversation with two readers has no
  /// moderator, so either side deleting is just the author rule.
  static bool canDelete(ChatMessage message, {required bool isModerator}) =>
      !message.isPending && (message.isMine || isModerator);

  /// Whether a message is one that can be pinned at all — whether *this
  /// member* may pin is the surface's to say, by offering the action or not.
  ///
  /// Never a locked one: pinning something you cannot read is pinning a
  /// message you are guessing about, for everyone. Never one only you can
  /// see either, which the server refuses anyway (`set_pinned`).
  static bool canPin(ChatMessage message) =>
      !message.isPending && !message.isLocked && !message.isEphemeral;
}
