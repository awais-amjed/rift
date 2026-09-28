import 'dart:collection';

import 'chat_message_ops.dart';

/// The newest rows of one open conversation, exactly as the server sent them,
/// held so they can be written to this device and drawn from there next time.
///
/// **Rows, not messages, on purpose.** A saved row goes back through the same
/// decrypt-and-verify path as one fresh off the network, so a copy read off
/// the disk is opened, locked or dropped by the rules that already exist — and
/// no second serialisation of `ChatMessage` has to keep up with every field
/// added to it.
///
/// Only what reached the live end of the conversation is fed in. A history
/// window the reader jumped to is not the tail, and saving it would draw the
/// wrong stretch of the conversation the next time it opens.
class SavedTail {
  /// How many rows are kept: one page, so the saved copy is exactly what the
  /// first fetch replaces.
  static const int size = ChatMessageOps.pageSize;

  /// By id, newest first — ids are `BIGSERIAL`, so they order as the rows were
  /// written.
  final SplayTreeMap<int, Map<String, dynamic>> _rows = SplayTreeMap(
    (a, b) => b.compareTo(a),
  );

  bool _changed = false;

  /// Newest first, the order a history page arrives in.
  List<Map<String, dynamic>> get rows => _rows.values.toList();

  bool get isEmpty => _rows.isEmpty;

  /// The newest page, replacing whatever was held.
  void replace(Iterable<Map<String, dynamic>> rows) {
    _rows.clear();
    merge(rows);
    _changed = true;
  }

  /// Rows that turned up at the live end, or were fetched by id while the
  /// reader was there. Kept to the newest [size].
  void merge(Iterable<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final id = _idOf(row);
      if (id == null) continue;
      _rows[id] = row;
      _changed = true;
    }
    while (_rows.length > size) {
      _rows.remove(_rows.lastKey());
    }
  }

  /// A row that changed in place — an edit, a reaction, a pin. Ignored when it
  /// is not held: a change to a message far up the history is no reason to
  /// start saving it.
  void update(Map<String, dynamic> row) {
    final id = _idOf(row);
    if (id == null || !_rows.containsKey(id)) return;
    _rows[id] = row;
    _changed = true;
  }

  /// A row that is gone. What was deleted must not come back from the disk.
  void remove(String messageId) {
    final id = int.tryParse(messageId);
    if (id == null || _rows.remove(id) == null) return;
    _changed = true;
  }

  void clear() {
    _rows.clear();
    _changed = false;
  }

  /// Whether anything changed since the last call, resetting the answer — so
  /// a save runs once per change rather than once per question.
  bool takeChanged() {
    final changed = _changed;
    _changed = false;
    return changed;
  }

  static int? _idOf(Map<String, dynamic> row) => int.tryParse('${row['id']}');
}
