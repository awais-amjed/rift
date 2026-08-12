import '../../data/classes/chat_message.dart';
import '../../data/classes/message_reaction.dart';

/// Pure list transforms shared by all three chat surfaces (channels, server
/// DMs, central DMs). They hold no state and touch no I/O, so the cubits keep
/// only their transport differences and this logic is unit-testable.
class ChatMessageOps {
  const ChatMessageOps._();

  /// How many rows a single history page asks for.
  static const int pageSize = 50;

  /// Sentinel for "no acknowledged message yet" when scanning for the oldest
  /// id — callers guard on an empty list before paginating.
  static const int _noOldestId = 0x7fffffffffffffff;

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
      if (m.id != pendingId) m else acked,
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

    final freshMineTexts = fresh
        .where((m) => m.isMine)
        .map((m) => m.text)
        .toSet();
    final kept = current
        .where(
          (m) => !(m.isPending && m.isMine && freshMineTexts.contains(m.text)),
        )
        .toList();
    return (merged: [...kept, ...fresh], fresh: fresh);
  }

  /// Replace every message's reactions with the server's authoritative counts
  /// (`{messageId: [{emoji, count, mine}]}`). Message content and order are
  /// untouched; a message missing from the map simply has none.
  static List<ChatMessage> withReactions(
    List<ChatMessage> messages,
    Map<String, dynamic> data,
  ) {
    final raw = (data['reactions'] as Map).cast<String, dynamic>();
    return messages.map((m) {
      final list = raw[m.id];
      final reactions = list == null
          ? const <MessageReaction>[]
          : (list as List)
                .cast<Map<String, dynamic>>()
                .map(MessageReaction.fromJson)
                .toList();
      return m.copyWith(reactions: reactions);
    }).toList();
  }

  /// Flip the local user's reaction locally so the tap feels instant. The
  /// server's counts overwrite this as soon as they come back.
  static List<ChatMessage> withOptimisticReaction(
    List<ChatMessage> messages, {
    required String messageId,
    required String emoji,
  }) {
    return messages.map((m) {
      if (m.id != messageId) return m;
      return m.copyWith(reactions: _toggled(m.reactions, emoji));
    }).toList();
  }

  static List<MessageReaction> _toggled(
    List<MessageReaction> reactions,
    String emoji,
  ) {
    final list = [...reactions];
    final idx = list.indexWhere((r) => r.emoji == emoji);
    if (idx == -1) {
      list.add(MessageReaction(emoji: emoji, count: 1, mine: true));
      return list;
    }
    final existing = list[idx];
    if (!existing.mine) {
      list[idx] = MessageReaction(
        emoji: emoji,
        count: existing.count + 1,
        mine: true,
      );
      return list;
    }
    final count = existing.count - 1;
    if (count <= 0) {
      list.removeAt(idx);
    } else {
      list[idx] = MessageReaction(emoji: emoji, count: count, mine: false);
    }
    return list;
  }
}
