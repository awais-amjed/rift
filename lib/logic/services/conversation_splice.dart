import '../../data/classes/dm_conversation.dart';

/// Putting one freshly-read conversation back into a list already on screen.
///
/// An incoming DM used to re-read the whole list; now it re-reads the one
/// conversation it belongs to, and this is where that
/// row goes. The list is newest-first by last message, so the row lands where
/// its last message puts it: at the top for a new message, where it was for an
/// edit.
class ConversationSplice {
  const ConversationSplice._();

  /// [conversations] with [peerId]'s row replaced by [updated] — or removed,
  /// when [updated] is null: the conversation is gone (every message deleted,
  /// or the peer blocked).
  static List<DmConversation> apply(
    List<DmConversation> conversations, {
    required String peerId,
    required DmConversation? updated,
  }) {
    final rest = [
      for (final conversation in conversations)
        if (conversation.peerId != peerId) conversation,
    ];
    if (updated == null) return rest;
    final position = rest.indexWhere(
      (conversation) => _newest(conversation) < _newest(updated),
    );
    return [...rest]..insert(position < 0 ? rest.length : position, updated);
  }

  /// Message ids are database sequence numbers, so they order by time. A row
  /// with nothing readable in it sorts last.
  static int _newest(DmConversation conversation) =>
      int.tryParse(conversation.lastMessage?.id ?? '') ?? -1;
}
