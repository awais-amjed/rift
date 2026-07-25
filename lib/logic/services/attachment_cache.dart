import 'dart:typed_data';

/// A small in-memory cache of decrypted attachment bytes, keyed by storage
/// path. Serves two roles:
///  * a sender's freshly-picked bytes are stashed here at upload time so their
///    own message renders instantly (no re-download of what they just sent);
///  * a receiver's downloaded+decrypted bytes are kept so scrolling past a
///    message doesn't re-fetch and re-decrypt it.
///
/// Bounded by insertion order (oldest evicted first) to cap memory — this is a
/// convenience cache, not storage; anything evicted is re-downloadable.
class AttachmentCache {
  AttachmentCache._();
  static final AttachmentCache instance = AttachmentCache._();

  static const int _maxEntries = 80;
  final Map<String, Uint8List> _entries = <String, Uint8List>{};

  Uint8List? get(String path) => _entries[path];

  bool has(String path) => _entries.containsKey(path);

  void put(String path, Uint8List bytes) {
    // Re-insert to mark as most-recent.
    _entries.remove(path);
    _entries[path] = bytes;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}
