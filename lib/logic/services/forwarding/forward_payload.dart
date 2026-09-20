import '../../../data/classes/chat_message.dart';
import '../../../data/classes/forwarded_message.dart';

/// Turning a message on screen into the block that travels with a forward.
abstract final class ForwardPayload {
  /// What [message] becomes when it is carried somewhere else: its words and
  /// its files, and nothing about where they came from.
  ///
  /// **Forwarding a forward flattens.** The inner block travels on as it is
  /// rather than being wrapped again — nesting has no bottom, and a reader
  /// gains nothing from being told how many hands a sentence passed through.
  static ForwardedMessage? of(ChatMessage message) {
    final inner = message.forwarded;
    if (inner != null) return inner;

    // A locked message has no content to carry — its text is empty because
    // the key never arrived, and forwarding it would send an empty card.
    if (message.isLocked) return null;

    final text = message.text;
    final forwarded = ForwardedMessage(
      text: text.length <= ForwardedMessage.maxText
          ? text
          : '${text.substring(0, ForwardedMessage.maxText)}…',
      attachments: message.attachments,
    );
    return forwarded.isEmpty ? null : forwarded;
  }

  /// Whether this message can be forwarded at all. Same rule as [of], asked
  /// before the menu is drawn so the action is absent rather than inert.
  static bool canForward(ChatMessage message) =>
      !message.isPending && of(message) != null;
}
