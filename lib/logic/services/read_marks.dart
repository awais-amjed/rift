import 'dart:async';

/// Spaces out the writes of read cursors: one conversation's is written at
/// most once every [every].
///
/// Somebody reading a busy channel marks it read as each message lands, and
/// each mark was a row written and a `read` sent to every one of their
/// devices: twenty messages in a burst, twenty of each, from every reader.
/// Now the first is written at once and the rest in one more when the time
/// is up.
///
/// A mark means "read up to the newest", so one waiting when its
/// conversation is left would, written later, also mark read whatever came
/// after. Whoever knows the screen changed calls [flush] first.
class ReadMarks<K> {
  ReadMarks(
    this._write, {
    this.every = const Duration(milliseconds: 1500),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Writes one cursor: [key] is what [mark] was given.
  final void Function(K key) _write;

  final Duration every;

  /// The time, which a test sets.
  final DateTime Function() _now;

  /// When each cursor was last written.
  final Map<K, DateTime> _last = {};

  /// The cursors to write again once [every] is up.
  final Map<K, Timer> _due = {};

  /// Write [key]'s cursor now, or once [every] has passed since the last.
  void mark(K key) {
    if (_due.containsKey(key)) return;
    final last = _last[key];
    final since = last == null ? null : _now().difference(last);
    if (since == null || since >= every) {
      _writeNow(key);
      return;
    }
    _due[key] = Timer(every - since, () {
      _due.remove(key);
      _writeNow(key);
    });
  }

  /// Write every cursor still waiting, now.
  void flush() {
    final due = _due.keys.toList();
    for (final key in due) {
      _due.remove(key)?.cancel();
      _writeNow(key);
    }
  }

  void _writeNow(K key) {
    final now = _now();
    _last[key] = now;
    // Only a cursor written within [every] can hold the next one back.
    if (_last.length > 64) {
      _last.removeWhere((_, at) => now.difference(at) >= every);
    }
    _write(key);
  }
}
