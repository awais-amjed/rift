import '../../data/classes/attachment.dart';
import '../../data/classes/chat_message.dart';

/// One line standing in for a whole message — what a reply quotes and what
/// the phone's action sheet shows above the menu.
///
/// Pure, and deliberately not a widget: the same sentence has to come out
/// wherever a message is referred to rather than rendered, and three places
/// each deciding what "a message with no text" says is three answers.
class MessageExcerpt {
  /// Past this the quote is a paragraph, and a quote that is longer than the
  /// reply under it has stopped being a reference.
  static const int maxLength = 120;

  /// A single line for [message]: its text with the line breaks taken out,
  /// or what it carried when it said nothing.
  ///
  /// **A locked message quotes as locked.** Its text is empty for the same
  /// reason the row is a placeholder — the key has not arrived — and calling
  /// that "Message" would state, in the one place a reader is looking for
  /// context, that there was nothing to read.
  static String of(ChatMessage message) {
    if (message.isLocked) return 'Message you cannot open yet';

    final text = _oneLine(message.text);
    if (text.isNotEmpty) return _clip(text);
    if (message.attachments.isNotEmpty) return _forAttachments(message);
    if (message.panel != null) return 'Panel';
    return 'Message';
  }

  /// Newlines, tabs and runs of spaces all collapse to one space. A quote is
  /// drawn on one line, and a message whose second line is blank would
  /// otherwise quote as its first word followed by a stretch of nothing.
  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _clip(String text) => text.length <= maxLength
      ? text
      : '${text.substring(0, maxLength).trimRight()}…';

  /// Named by what they are rather than counted, because "2 attachments" is
  /// the one description that tells a reader nothing they wanted.
  static String _forAttachments(ChatMessage message) {
    final kinds = message.attachments.map((a) => a.kind).toSet();
    final only = kinds.length == 1 ? kinds.first : null;
    final several = message.attachments.length > 1;
    return switch (only) {
      AttachmentKind.image => several ? 'Images' : 'Image',
      AttachmentKind.audio => several ? 'Voice messages' : 'Voice message',
      AttachmentKind.file => several ? 'Files' : 'File',
      null => 'Attachments',
    };
  }
}
