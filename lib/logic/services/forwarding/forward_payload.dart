import '../../../data/classes/chat_message.dart';
import '../../../data/classes/forwarded_message.dart';

/// Turning a message on screen into the block that travels with a forward.
abstract final class ForwardPayload {
  /// What [message] becomes when it is carried somewhere else.
  ///
  /// [source] is where the forwarder says it came from — "#general in Proxy
  /// Test", or a person's name. Passed in rather than read off the message,
  /// because the message does not know which room it is being read in.
  ///
  /// **Forwarding a forward flattens.** The inner block travels on with the
  /// author it already claimed, rather than being wrapped again: nesting has
  /// no bottom, and the second wrapper would attribute the words to whoever
  /// forwarded them to you — which is the one thing a forward must not start
  /// doing as it is passed along.
  static ForwardedMessage? of(ChatMessage message, {String? source}) {
    final inner = message.forwarded;
    if (inner != null) return inner;

    // A locked message has no content to carry — its text is empty because
    // the key never arrived, and forwarding it would post an empty quote
    // under somebody's name.
    if (message.isLocked) return null;
    if (message.text.isEmpty && message.attachments.isEmpty) return null;

    final text = message.text;
    return ForwardedMessage(
      authorName: message.authorName,
      sentAt: message.sentAt,
      text: text.length <= ForwardedMessage.maxText
          ? text
          : '${text.substring(0, ForwardedMessage.maxText)}…',
      attachments: message.attachments,
      source: source,
    );
  }

  /// Whether this message can be forwarded at all. Same rule as [of], asked
  /// before the menu is drawn so the action is absent rather than inert.
  static bool canForward(ChatMessage message) =>
      !message.isPending && of(message) != null;
}
