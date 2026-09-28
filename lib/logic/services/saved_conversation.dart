import 'dart:async';

import '../../data/classes/message_cache_slot.dart';
import 'message_cache.dart';
import 'saved_tail.dart';

/// Fetches a conversation's newest page, newest first, or null when it cannot.
/// See [SavedConversation.noteSent].
typedef LatestPage = Future<List<Map<String, dynamic>>?> Function();

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
  LatestPage? _latestPage;

  /// This device sent into the open conversation since it was opened — see
  /// [noteSent].
  bool _sent = false;

  /// Point at [slot] and read what was saved there, or null.
  ///
  /// [latestPage] reads the conversation's newest page again; it is how this
  /// device's own messages reach the copy (see [noteSent]).
  ///
  /// Whatever the previous conversation had pending must already be on its
  /// way — [flush] it with `leaving: true` before calling this, since from
  /// here on everything is about [slot].
  Future<Map<String, dynamic>?> open(
    String? seed,
    MessageCacheSlot slot, {
    LatestPage? latestPage,
  }) {
    _timer?.cancel();
    _slot = slot;
    _seed = seed;
    _latestPage = latestPage;
    _sent = false;
    _tail.clear();
    if (seed == null) return Future.value();
    return _cache.read(seed, slot);
  }

  /// This device's message was stored.
  ///
  /// Its row never comes through the fetches that feed the copy — the sender
  /// drew it already, and a send answers with an id, not a row. So when the
  /// conversation is left, the newest page is read once more and saved in
  /// place of the tail: **one request per visit in which something was
  /// sent**, however many messages that was, and none for a visit spent
  /// reading. A visit that ends without being left — the app killed —
  /// saves a copy missing those sends, which the next open's fresh page puts
  /// right a moment later.
  void noteSent() {
    _sent = true;
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

  /// Write now, if anything changed since the last write. [leaving] is the
  /// conversation being left — opened over, closed, or the app shutting down
  /// — which is the one time this device's own sends are fetched in.
  ///
  /// Everything written is read before the first `await`, so a flush started
  /// just as another conversation opens saves the one being left — its rows,
  /// its slot, and whatever [extras] says about it — not a mixture of two.
  Future<void> flush({bool leaving = false}) async {
    _timer?.cancel();
    final slot = _slot;
    final seed = _seed;
    final latestPage = leaving && _sent ? _latestPage : null;
    if (latestPage != null) _sent = false;
    final changed = _tail.takeChanged();
    if (slot == null || seed == null || (!changed && latestPage == null)) {
      return;
    }
    final extras = _extras();
    final canSave = _canSave();
    final rows = SavedTail()..replace(_tail.rows);

    if (latestPage != null) {
      try {
        final page = await latestPage();
        if (page != null) rows.replace(page);
      } catch (_) {
        // Saved as it stood instead; the next open's fresh page fills in.
      }
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
    _sent = false;
    _latestPage = null;
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
