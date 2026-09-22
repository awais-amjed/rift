import '../../data/classes/chat_message.dart';
import '../../data/classes/pending_attachment.dart';
import '../../data/enums/error_code.dart';

/// One send that did not land, and everything a second attempt would need.
///
/// The row is the message exactly as it is drawn — text, author, the time it
/// was written — so restoring it after a navigation is a matter of putting it
/// back, not of rebuilding it. The attachments ride alongside because they are
/// the one input a retry needs that the row does not carry: [ChatMessage] holds
/// *uploaded* attachments, and a send that failed may never have got that far.
class OutboxEntry {
  /// Which conversation it belongs to — a channel id, or a peer id.
  final String destination;

  /// The failed row, `isPending` and `sendFailed` both true.
  final ChatMessage row;

  /// The local bytes, still unuploaded. Empty for a plain text message.
  final List<PendingAttachment> attachments;

  const OutboxEntry({
    required this.destination,
    required this.row,
    this.attachments = const [],
  });

  String get pendingId => row.id;
  String get text => row.text;
}

/// Sends that failed on the way out and are waiting to be told to try again.
///
/// Rift has no local message store, and this is deliberately not the start of
/// one: it holds only what has *not* been sent, in memory, for as long as the
/// app is open. A message that reached the server is the server's; a message
/// that did not is nobody's unless something keeps it, and what used to keep it
/// was nothing at all — a failed send dropped its row and its text with it, so
/// a sentence typed in a tunnel was gone by the time you were out of it.
///
/// Nothing here re-sends on its own. The entries are held, the rows say so, and
/// a person decides. That is the same rule the rest of the app follows about
/// asserting things the server has not confirmed: a queue that empties itself
/// while nobody is looking can deliver a sentence hours after it stopped being
/// true.
///
/// It survives leaving a conversation and coming back — [restoreInto] is how
/// the rows return — because a "not sent" message that vanishes on the first
/// click elsewhere is exactly the loss this exists to stop.
class Outbox {
  final Map<String, OutboxEntry> _held = {};

  /// Whether a failed send is worth keeping at all.
  ///
  /// Only a connection failure. Everything else is the server having answered
  /// — a quota, a policy, an unfriending — and those rows are taken away with
  /// an explanation instead, because there is nothing a retry would change.
  static bool canRetry(String? errorCode) => ErrorCode.isRetryable(errorCode);

  /// Keep a failed send. Replaces any entry under the same pending id.
  void hold(OutboxEntry entry) => _held[entry.pendingId] = entry;

  /// Hand an entry back and stop holding it — the retry primitive.
  ///
  /// Removing and returning in one step is what makes a double-tap safe: the
  /// second one finds nothing and does nothing, where a "read, then send, then
  /// remove" would send twice.
  OutboxEntry? take(String pendingId) => _held.remove(pendingId);

  /// Forget one entry without retrying it — the row is going away.
  void drop(String pendingId) => _held.remove(pendingId);

  /// Forget the entries behind rows a merge has just retired.
  ///
  /// A send can time out *after* the server stored it. When that message comes
  /// back, the merge retires the row it belongs to — and the entry behind it
  /// has to go too, or reopening the conversation would offer to send a
  /// message that is already in it.
  void dropRetired(Iterable<String> pendingIds) => pendingIds.forEach(drop);

  /// Forget everything for one conversation.
  void dropDestination(String destination) =>
      _held.removeWhere((_, entry) => entry.destination == destination);

  void clear() => _held.clear();

  bool holds(String pendingId) => _held.containsKey(pendingId);

  int get length => _held.length;

  /// The held rows for one conversation, oldest first.
  ///
  /// Ordered by when they were written rather than by when they failed: they
  /// are drawn among real messages, and a list that is chronological except for
  /// the failures reads as though the failures happened to somebody else.
  List<ChatMessage> rowsFor(String destination) =>
      (_held.values.where((e) => e.destination == destination).toList()
            ..sort((a, b) => a.row.sentAt.compareTo(b.row.sentAt)))
          .map((e) => e.row)
          .toList();

  /// Put the held rows for [destination] back at the end of a freshly fetched
  /// list — what a conversation calls after loading its history.
  ///
  /// At the end rather than in date order, because that is where an unsent
  /// message belongs: below everything that did send, where the composer is,
  /// and where it was when it failed.
  List<ChatMessage> restoreInto(
    List<ChatMessage> messages,
    String destination,
  ) {
    final rows = rowsFor(destination);
    if (rows.isEmpty) return messages;
    final known = messages.map((m) => m.id).toSet();
    return [...messages, ...rows.where((r) => !known.contains(r.id))];
  }
}
