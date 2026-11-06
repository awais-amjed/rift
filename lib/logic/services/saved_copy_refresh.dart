import 'dart:async';

import '../../data/classes/message_cache_slot.dart';
import 'chat_message_ops.dart';
import 'message_cache.dart';
import 'saved_conversation.dart';
import 'saved_tail.dart';

/// A conversation's rows newer than [afterId], or its newest page with none;
/// null when the read failed.
typedef RowsAfter = Future<List<Map<String, dynamic>>?> Function(int? afterId);

/// Brings a conversation's saved copy up to date while it is not open — one
/// a message just arrived in that rang for it, a notification or a chime.
///
/// Opening the conversation draws its saved copy at once and then asks the
/// server for the page. The copy was saved when the conversation was last
/// left, so it is the one thing on screen that lacks the message that rang:
/// that arrived a ping or more after the click, however fast everything else
/// was. Read here, while the notification or the badge is being looked at,
/// the copy has it, and the click shows it straight away.
///
/// Only what is newer than the copy's newest row is asked for, usually the
/// one message, and merged in. More than a page of it, and the newest page
/// replaces the copy instead, so it never holds a gap.
///
/// Only a conversation that already has a copy is brought up to date. A
/// channel's copy carries the keys it is opened with, and without one there
/// is nothing to open new rows with; nor does a conversation never opened
/// here need one to start now.
///
/// One read at a time per conversation: a message arriving while one is on
/// its way asks for one more after it, so a burst is two reads, not one per
/// message.
class SavedCopyRefresh {
  final MessageCache _cache;

  SavedCopyRefresh({MessageCache? cache})
    : _cache = cache ?? MessageCache.instance;

  /// Conversations being read, and whether another read is owed after.
  final Map<String, bool> _running = {};

  /// Read what [slot] lacks with [rowsAfter] and save it there, keeping
  /// whatever else the copy holds (a channel's keys, the names drawn).
  void refresh(String? seed, MessageCacheSlot slot, RowsAfter rowsAfter) {
    if (seed == null) return;
    final key = '${slot.scope}|${slot.conversation}';
    if (_running.containsKey(key)) {
      _running[key] = true;
      return;
    }
    _running[key] = false;
    unawaited(_run(key, seed, slot, rowsAfter));
  }

  Future<void> _run(
    String key,
    String seed,
    MessageCacheSlot slot,
    RowsAfter rowsAfter,
  ) async {
    try {
      do {
        _running[key] = false;
        if (!await _refreshOnce(seed, slot, rowsAfter)) break;
      } while (_running[key] ?? false);
    } finally {
      _running.remove(key);
    }
  }

  /// Whether the copy is up to date. Read again after the rows are in, not
  /// only before: the conversation may have been opened and left in between,
  /// and what it saved then is kept, with the new rows added.
  Future<bool> _refreshOnce(
    String seed,
    MessageCacheSlot slot,
    RowsAfter rowsAfter,
  ) async {
    try {
      final before = await _cache.read(seed, slot);
      if (before == null) return false;
      final newest = _newestId(before);
      var rows = await rowsAfter(newest);
      var whole = newest == null;
      if (rows != null && !whole && rows.length >= ChatMessageOps.pageSize) {
        rows = await rowsAfter(null);
        whole = true;
      }
      if (rows == null) return false;
      if (rows.isEmpty && !whole) return true;
      final saved = await _cache.read(seed, slot);
      if (saved == null) return false;
      final tail = SavedTail();
      if (!whole) tail.replace(SavedConversation.rowsOf(saved));
      tail.merge(rows);
      if (tail.isEmpty) return true;
      await _cache.write(seed, slot, {...saved, 'rows': tail.rows});
      return true;
    } catch (_) {
      // The next open's fresh page fills in, as it always did.
      return false;
    }
  }

  static int? _newestId(Map<String, dynamic> saved) {
    final rows = SavedConversation.rowsOf(saved);
    if (rows.isEmpty) return null;
    final id = (SavedTail()..replace(rows)).rows.first['id'];
    return id is int ? id : int.tryParse('$id');
  }
}
