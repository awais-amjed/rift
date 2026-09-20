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

/// Paging backwards through history until a message is in the loaded list.
///
/// One implementation for all three chat surfaces. They differ only in which
/// cubit holds the list, and three copies of a loop with a page cap in it is
/// three chances to leave the cap off.
abstract final class QuoteLookup {
  /// How far back a jump will page before giving up.
  ///
  /// Fifty messages a page, so this is two and a half thousand — far enough
  /// to reach anything somebody is plausibly still talking about, and short
  /// enough that answering a year-old message does not quietly pull the
  /// whole channel onto the device. Past it the reader is told, rather than
  /// left watching a spinner that has no end.
  static const int maxPages = 50;

  static Future<bool> pageUntilLoaded({
    required bool Function() isLoaded,
    required bool Function() hasMore,
    required int Function() loadedCount,
    required Future<void> Function() loadMore,
    int maxPages = QuoteLookup.maxPages,
  }) async {
    for (var page = 0; page < maxPages; page++) {
      if (isLoaded()) return true;
      if (!hasMore()) return false;

      final before = loadedCount();
      await loadMore();
      // A page that added no rows is the far end, whatever the flag says.
      // Without this, a `loadMore` that quietly declines — one already in
      // flight is enough — spins the loop to its cap on every tap.
      if (loadedCount() == before) return isLoaded();
    }
    return isLoaded();
  }
}
