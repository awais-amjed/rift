import '../../data/classes/chat_message.dart';

/// What came back when a client went looking for the message a reply names.
///
/// Three outcomes, not two, and keeping them apart is the whole point of the
/// type. "I could not find it" and "it is not there" are different facts
/// about the world, and a reader told the second when the first is true has
/// been informed that somebody deleted something they did not
/// (ARCHITECTURE.md §4 makes the same distinction one level down, between a
/// message that is locked and one that was dropped).
class QuotedMessage {
  /// The message, when there is one to show.
  final ChatMessage? message;

  /// The server answered, and there is no such row. Somebody deleted it.
  final bool deleted;

  /// It is real and readable, just not in the page the reader has loaded.
  const QuotedMessage.found(ChatMessage this.message) : deleted = false;

  /// Asked, and told there is nothing there.
  const QuotedMessage.deleted() : message = null, deleted = true;

  /// Could not tell: the request failed, the conversation moved on, or the
  /// row came back and did not verify. Nothing is claimed.
  const QuotedMessage.unknown() : message = null, deleted = false;

  bool get isFound => message != null;
}
