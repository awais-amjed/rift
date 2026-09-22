import '../../data/classes/api_response.dart';
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

  /// What a lookup's [response] means, once [open] has turned its row into a
  /// message.
  ///
  /// Shared by every conversation that can quote — a channel, a server DM, a
  /// central DM — which fetch and open a row each in their own way but read
  /// the answer by one rule. [stillOpen] is asked *after* the request: an
  /// answer about a conversation the reader has since left is not one.
  static Future<QuotedMessage> settle(
    APIResponse response, {
    required bool Function() stillOpen,
    required Future<ChatMessage?> Function(Map<String, dynamic> row) open,
  }) async {
    if (!response.success || !stillOpen()) return const QuotedMessage.unknown();
    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) return const QuotedMessage.deleted();
    final message = await open((row as Map).cast<String, dynamic>());
    return message == null
        ? const QuotedMessage.unknown()
        : QuotedMessage.found(message);
  }
}
