import '../../data/classes/chat_message.dart';

/// Pure list transforms shared by all three chat surfaces (channels, server
/// DMs, central DMs). They hold no state and touch no I/O, so the cubits keep
/// only their transport differences and this logic is unit-testable.
///
/// Reactions have their own file — see `ReactionOps`.
class ChatMessageOps {
  const ChatMessageOps._();

  /// How many rows a single history page asks for.
  static const int pageSize = 50;

  /// Sentinel for "no acknowledged message yet" when scanning for the oldest
  /// id — callers guard on an empty list before paginating. It has to be
  /// *above* every real id, because it is the seed of a running minimum and
  /// reaches the API as "everything before this".
  ///
  /// `2^53 - 1` rather than the 64-bit maximum: an `int` on the web is a
  /// double, and `0x7fffffffffffffff` has no exact representation there —
  /// dart2js refuses to compile the literal at all. This is exact on every
  /// target and still far beyond anything a `bigserial` will hand out.
  static const int _noOldestId = 9007199254740991;

  /// Trim an over-fetched page back to [limit] and report whether more exists.
  ///
  /// Every history read asks the database for `limit + 1` rows; the row past
  /// the page is what proves there is another page. Inferring it from a full
  /// page instead — the obvious shortcut — lies whenever the history is an
  /// exact multiple of the page size: 50 messages would promise a fifty-first,
  /// and the reader who scrolls back gets a spinner for a page that comes back
  /// empty. One spare row on the wire is cheaper than a count.
  static ({List<T> rows, bool hasMore}) splitPage<T>(
    List<T> rows, {
    int limit = pageSize,
  }) => (
    rows: rows.length > limit ? rows.sublist(0, limit) : rows,
    hasMore: rows.length > limit,
  );

  /// The newest server-acknowledged id. Pending messages carry non-numeric
  /// ids and are skipped.
  static int latestId(List<ChatMessage> messages) => messages
      .where((m) => !m.isPending)
      .fold(0, (max, m) => int.parse(m.id) > max ? int.parse(m.id) : max);

  /// The oldest server-acknowledged id — the cursor for scroll-up pagination.
  static int oldestId(List<ChatMessage> messages) => messages
      .where((m) => !m.isPending)
      .map((m) => int.parse(m.id))
      .fold(_noOldestId, (min, id) => id < min ? id : min);

  /// The acknowledged ids, for APIs that take a batch of message ids.
  static List<int> ackedIds(List<ChatMessage> messages) => messages
      .where((m) => !m.isPending)
      .map((m) => int.tryParse(m.id))
      .whereType<int>()
      .toList();

  static List<ChatMessage> removePending(
    List<ChatMessage> messages,
    String pendingId,
  ) => messages.where((m) => m.id != pendingId).toList();

  /// Swap an optimistic bubble for the row the server acknowledged.
  static List<ChatMessage> replacePending(
    List<ChatMessage> messages, {
    required String pendingId,
    required ChatMessage acked,
  }) => [
    for (final m in messages)
      // The acked row remembers the id it was drawn under, so the swap is a
      // row changing rather than one row leaving and another arriving. See
      // [ChatMessage.sentAsId].
      if (m.id != pendingId) m else acked.copyWith(sentAsId: pendingId),
  ];

  /// Apply an edit locally: swap [text] in and stamp [editedAt] on one row.
  /// Attachments and reactions ride along untouched.
  static List<ChatMessage> applyEdit(
    List<ChatMessage> messages, {
    required String messageId,
    required String text,
    required DateTime editedAt,
  }) => [
    for (final m in messages)
      if (m.id != messageId) m else m.copyWith(text: text, editedAt: editedAt),
  ];

  /// Drop one row — a delete is hard, so there is no tombstone to render.
  static List<ChatMessage> removeMessage(
    List<ChatMessage> messages,
    String messageId,
  ) => messages.where((m) => m.id != messageId).toList();

  /// Swap in a freshly re-read row, keeping its place in the list.
  ///
  /// A message we don't hold is left out rather than appended: the row may sit
  /// outside the loaded window entirely, and dropping it into the end of the
  /// list would put it out of order.
  static List<ChatMessage> replaceMessage(
    List<ChatMessage> messages,
    ChatMessage message,
  ) => [
    for (final m in messages)
      if (m.id != message.id) m else message,
  ];

  /// Fold a freshly-fetched page into what's on screen.
  ///
  /// Rows we already hold are dropped, and a pending bubble is retired only
  /// when its exact content came back from the server — other in-flight sends
  /// keep their bubbles. [fresh] is what actually arrived, so callers can
  /// notify or clear typing state off it.
  static ({List<ChatMessage> merged, List<ChatMessage> fresh}) mergeIncoming({
    required List<ChatMessage> current,
    required List<ChatMessage> incoming,
  }) {
    final known = current.where((m) => !m.isPending).map((m) => m.id).toSet();
    final fresh = incoming.where((m) => !known.contains(m.id)).toList();
    if (fresh.isEmpty) return (merged: current, fresh: const []);

    // One acknowledged row retires one bubble, oldest first — a count, not a
    // set of texts. Matching on membership let a single arriving row retire
    // *every* pending bubble that happened to say the same thing: send "ok"
    // twice and the first one coming back took both, leaving the second send's
    // own acknowledgement with no bubble to replace. That message then existed
    // on the server and nowhere on screen until the chat was reopened.
    final unclaimed = <String, int>{};
    for (final m in fresh) {
      if (m.isMine) unclaimed[m.text] = (unclaimed[m.text] ?? 0) + 1;
    }
    final kept = <ChatMessage>[];
    for (final m in current) {
      final claims = unclaimed[m.text] ?? 0;
      if (m.isPending && m.isMine && claims > 0) {
        unclaimed[m.text] = claims - 1;
        continue;
      }
      kept.add(m);
    }
    return (merged: [...kept, ...fresh], fresh: fresh);
  }
}
