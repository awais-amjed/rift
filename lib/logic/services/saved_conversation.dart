import 'dart:async';

import '../../data/classes/message_cache_slot.dart';
import 'message_cache.dart';
import 'saved_tail.dart';

/// Fetches a conversation's rows with ids above [afterId], or none when it
/// cannot. See [SavedConversation.noteSent].
typedef RowsAfter = Future<List<Map<String, dynamic>>> Function(int afterId);

/// The saved copy of whichever conversation is open: where it goes, the rows
/// it will hold, and writing them once a burst of changes settles.
///
/// Shared by the three chat cubits — channels, server DMs, central DMs —
/// which differ only in what they keep beside the rows, handed in as
/// [extras]. A channel keeps its keys there, because its keys come from the
/// server; a DM's key is worked out on the device and needs no copy.
class SavedConversation {
  final MessageCache _cache;
  final Map<String, dynamic> Function() _extras;
  final bool Function() _canSave;

  /// [canSave] is asked at write time: false leaves the previous copy where
  /// it is rather than replacing it with one that could not be opened.
  SavedConversation({
    MessageCache? cache,
    Map<String, dynamic> Function()? extras,
    bool Function()? canSave,
  }) : _cache = cache ?? MessageCache.instance,
       _extras = extras ?? _none,
       _canSave = canSave ?? _always;

  /// How long changes are left to settle before they are written, so a busy
  /// conversation is one write every few seconds rather than one per message.
  static const saveAfter = Duration(seconds: 2);

  final SavedTail _tail = SavedTail();
  MessageCacheSlot? _slot;
  String? _seed;
  Timer? _timer;
  RowsAfter? _rowsAfter;

  /// The lowest id this device sent since the last write, whose rows the
  /// tail has not seen — see [noteSent].
  int? _sentFrom;

  /// Point at [slot] and read what was saved there, or null.
  ///
  /// [rowsAfter] fetches the open conversation's rows after an id; it is how
  /// this device's own messages reach the copy (see [noteSent]).
  ///
  /// Whatever the previous conversation had pending must already be on its
  /// way — [flush] it before calling this, since from here on everything is
  /// about [slot].
  Future<Map<String, dynamic>?> open(
    String? seed,
    MessageCacheSlot slot, {
    RowsAfter? rowsAfter,
  }) {
    _timer?.cancel();
    _slot = slot;
    _seed = seed;
    _rowsAfter = rowsAfter;
    _sentFrom = null;
    _tail.clear();
    if (seed == null) return Future.value();
    return _cache.read(seed, slot);
  }

  /// This device's message was stored as [messageId].
  ///
  /// Its row is not fetched on the way in — the sender already drew it, and
  /// the send answers with an id, not a row. So it is fetched when the copy
  /// is next written, together with any others sent in the meantime: one
  /// request for a burst of messages rather than one each. Without it, a copy
  /// would hold everybody's messages but your own.
  void noteSent(String messageId) {
    final id = int.tryParse(messageId);
    if (id == null) return;
    final from = _sentFrom;
    _sentFrom = from == null || id < from ? id : from;
    _schedule();
  }

  /// The newest page, fresh from the server.
  void replace(List<Map<String, dynamic>> rows) {
    _tail.replace(rows);
    _schedule();
  }

  /// Rows that arrived at the live end.
  void merge(List<Map<String, dynamic>> rows) {
    _tail.merge(rows);
    _schedule();
  }

  /// A row changed in place.
  void update(Map<String, dynamic> row) {
    _tail.update(row);
    _schedule();
  }

  /// A row deleted.
  void remove(String messageId) {
    _tail.remove(messageId);
    _schedule();
  }

  /// Write now, if anything changed since the last write.
  ///
  /// Everything written is read before the first `await`, so a flush started
  /// just as another conversation opens saves the one being left — its rows,
  /// its slot, and whatever [extras] says about it — not a mixture of two.
  Future<void> flush() async {
    _timer?.cancel();
    final slot = _slot;
    final seed = _seed;
    final sentFrom = _sentFrom;
    final rowsAfter = _rowsAfter;
    _sentFrom = null;
    final changed = _tail.takeChanged();
    if (slot == null || seed == null || (!changed && sentFrom == null)) {
      return;
    }
    final extras = _extras();
    final canSave = _canSave();
    final rows = SavedTail()..replace(_tail.rows);

    if (sentFrom != null && rowsAfter != null) {
      final sent = await rowsAfter(sentFrom - 1);
      rows.merge(sent);
      // Into the live tail too, if it is still this conversation's, so the
      // next write does not have to ask again.
      if (_slot == slot) _tail.merge(sent);
    }

    // Nothing left in it: a conversation emptied since, so there is nothing
    // to draw next time and nothing to keep.
    if (rows.isEmpty) {
      await _cache.forget(seed, slot);
      return;
    }
    if (!canSave) return;
    await _cache.write(seed, slot, {...extras, 'rows': rows.rows});
  }

  /// Drop whatever was pending without writing it, and forget which
  /// conversation was open — for an account signing out, whose copies are
  /// being wiped rather than kept.
  void discard() {
    _timer?.cancel();
    _tail.clear();
    _sentFrom = null;
    _rowsAfter = null;
    _slot = null;
    _seed = null;
  }

  /// Stop waiting to write. Call [flush] first to keep what was pending.
  void dispose() => _timer?.cancel();

  /// The rows in a copy [open] returned, newest first.
  static List<Map<String, dynamic>> rowsOf(Map<String, dynamic> saved) =>
      (saved['rows'] as List? ?? const []).cast<Map<String, dynamic>>();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(saveAfter, () => unawaited(flush()));
  }

  static Map<String, dynamic> _none() => const {};
  static bool _always() => true;
}
