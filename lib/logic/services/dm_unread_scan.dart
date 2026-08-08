/// Derives per-conversation unread counts from a batch of raw DM rows.
///
/// Central DMs have no `notifications` table to count — unlike a self-hosted
/// server, nothing fans out a row per recipient, because the client already
/// sees every message it is allowed to see (RLS + Realtime on `dm_messages`).
/// So unread is *derived*: the conversation refresh already pulls every recent
/// envelope, and anything inbound above the peer's read cursor hasn't been read.
///
/// This is the whole rule, kept pure so its edges are testable: a message is
/// unread when it was addressed to you, came from that peer, and its id is
/// above the cursor you last stored for them.
class DmUnreadScan {
  /// peer id → how many of their messages are unread. Zero counts are absent.
  final Map<String, int> counts;

  /// peer id → the newest inbound message id in this batch. This is what a
  /// "mark read" writes back as the new cursor, so it must come from the same
  /// scan as [counts] — a cursor from a later batch would skip messages.
  final Map<String, int> latestInbound;

  const DmUnreadScan({required this.counts, required this.latestInbound});

  /// Scans [rows] (raw `dm_messages` rows, either direction, any order).
  ///
  /// Rows the caller sent are skipped: your own message is never unread, and
  /// sending is not the same as having read what came before it — the cursor
  /// only moves when the conversation is actually looked at.
  static DmUnreadScan of({
    required List<Map<String, dynamic>> rows,
    required String myUserId,
    required Map<String, int> cursors,
  }) {
    final counts = <String, int>{};
    final latestInbound = <String, int>{};

    for (final row in rows) {
      if (row['recipient_id'] != myUserId) continue;
      final peerId = row['sender_id'] as String?;
      final id = row['id'];
      if (peerId == null || id is! int) continue;

      if (id > (latestInbound[peerId] ?? 0)) latestInbound[peerId] = id;
      if (id > (cursors[peerId] ?? 0)) {
        counts[peerId] = (counts[peerId] ?? 0) + 1;
      }
    }

    return DmUnreadScan(counts: counts, latestInbound: latestInbound);
  }
}
