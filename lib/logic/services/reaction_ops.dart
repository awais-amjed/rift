import '../../data/classes/chat_message.dart';
import '../../data/classes/message_reaction.dart';

/// Pure reaction transforms, shared by all three chat surfaces (channels,
/// server DMs, central DMs) and by the repositories that read them.
///
/// Reactions are the one part of a message that is **not** end-to-end
/// encrypted — the server stores one row per person per emoji and can see them
/// (ARCHITECTURE.md §4). That is why the tallying lives here rather than in
/// SQL: the raw rows come back with the message page, and folding them into
/// counts is cheap, testable, and the same on every surface.
class ReactionOps {
  const ReactionOps._();

  /// Fold one message's raw reaction rows (`{user_id, emoji}`) into the
  /// aggregated wire shape, `[{emoji, count, mine}]`, in first-seen order.
  ///
  /// [userId] is who "mine" means; a null one (signed out mid-read) simply
  /// makes nothing mine rather than throwing.
  static List<Map<String, dynamic>> aggregate(
    Iterable<Map<String, dynamic>> rows, {
    required String? userId,
  }) {
    final byEmoji = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final emoji = row['emoji'] as String;
      final agg = byEmoji.putIfAbsent(
        emoji,
        () => {'emoji': emoji, 'count': 0, 'mine': false},
      );
      agg['count'] = (agg['count'] as int) + 1;
      if (userId != null && row['user_id'] == userId) agg['mine'] = true;
    }
    return byEmoji.values.toList();
  }

  /// The same fold across rows spanning several messages, keyed by message id
  /// — the shape the standalone reaction read answers with.
  static Map<String, dynamic> byMessage(
    Iterable<Map<String, dynamic>> rows, {
    required String? userId,
    String idKey = 'message_id',
  }) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped.putIfAbsent('${row[idKey]}', () => []).add(row);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: aggregate(entry.value, userId: userId),
    };
  }

  /// Read the aggregated reactions a message row arrived with.
  static List<MessageReaction> fromRow(Map<String, dynamic> row) =>
      MessageReaction.listFrom(row['reactions']);

  /// Replace every message's reactions with the server's authoritative counts
  /// (`{messageId: [{emoji, count, mine}]}`). Message content and order are
  /// untouched; a message missing from the map simply has none.
  ///
  /// Only for a read that asked about *every* loaded message — see
  /// [withReactionsFor] for the single-message case, which must not blank the
  /// messages it didn't ask about.
  static List<ChatMessage> withReactions(
    List<ChatMessage> messages,
    Map<String, dynamic> data,
  ) {
    final raw = (data['reactions'] as Map).cast<String, dynamic>();
    return [
      for (final m in messages)
        m.copyWith(reactions: MessageReaction.listFrom(raw[m.id])),
    ];
  }

  /// Apply an authoritative answer about one message, leaving the rest alone.
  ///
  /// An absent entry means that message has no reactions left — removing your
  /// last one is exactly the case that returns nothing — so it clears rather
  /// than skips.
  static List<ChatMessage> withReactionsFor(
    List<ChatMessage> messages, {
    required String messageId,
    required Map<String, dynamic> data,
  }) {
    final raw = (data['reactions'] as Map).cast<String, dynamic>();
    return [
      for (final m in messages)
        if (m.id != messageId)
          m
        else
          m.copyWith(reactions: MessageReaction.listFrom(raw[messageId])),
    ];
  }

  /// Flip the local user's reaction locally so the tap feels instant. The
  /// server's counts overwrite this as soon as they come back.
  static List<ChatMessage> withOptimisticReaction(
    List<ChatMessage> messages, {
    required String messageId,
    required String emoji,
  }) => [
    for (final m in messages)
      if (m.id != messageId)
        m
      else
        m.copyWith(reactions: _toggled(m.reactions, emoji)),
  ];

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
