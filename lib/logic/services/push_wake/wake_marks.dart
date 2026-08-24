import 'dart:convert';
import 'dart:io';

import '../storage_namespace.dart';

/// The newest message this device has already been told about, per
/// conversation.
///
/// Without it every wake would re-announce the same message. The server's
/// answer to "what is unread" is relative to the read cursor, which only moves
/// when somebody actually opens the conversation — so a message that arrived
/// and was not read stays unread, and a second doorbell for a *different*
/// conversation would otherwise raise it again.
///
/// It is a high-water mark and only moves forward. Nothing here decides what
/// is unread; that is still the read cursor's job. This only decides what has
/// already been said out loud.
class WakeMarks {
  final Map<String, int> _marks;

  WakeMarks(Map<String, int> marks) : _marks = marks;

  static const _fileName = 'push_wake_marks.json';

  /// How many conversations to remember. Past this the oldest-marked are
  /// dropped: a conversation nobody has been notified about in hundreds of
  /// conversations' worth of traffic is not one a duplicate would be noticed in.
  static const maxEntries = 200;

  int operator [](String scope) => _marks[scope] ?? 0;

  /// Record that [scope] has been announced up to [messageId]. Never moves a
  /// mark backwards — two wakes can overlap, and the later one must not undo
  /// what the earlier one said.
  void mark(String scope, int messageId) {
    if (messageId > (_marks[scope] ?? 0)) _marks[scope] = messageId;
  }

  /// Whether [messageId] is something this device has not been told about.
  bool isFresh(String scope, int messageId) => messageId > this[scope];

  static Future<File> _file() async {
    final dir = await StorageNamespace.profileDirectory(
      StorageNamespace.apply(),
    );
    await Directory(dir).create(recursive: true);
    return File('$dir/$_fileName');
  }

  static Future<WakeMarks> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return WakeMarks({});
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return WakeMarks({});
      return WakeMarks({
        for (final entry in json.entries)
          if (entry.value is int) '${entry.key}': entry.value as int,
      });
    } catch (_) {
      return WakeMarks({});
    }
  }

  Future<void> save() async {
    try {
      final trimmed = pruned();
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(trimmed._marks), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // Best-effort: the cost of losing this is one repeated notification.
    }
  }

  /// The [maxEntries] highest-numbered marks. Message ids rise over time, so
  /// the highest are also the most recently spoken about.
  WakeMarks pruned() {
    if (_marks.length <= maxEntries) return this;
    final entries = _marks.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return WakeMarks({
      for (final entry in entries.take(maxEntries)) entry.key: entry.value,
    });
  }

  Map<String, int> get asMap => Map.unmodifiable(_marks);
}
