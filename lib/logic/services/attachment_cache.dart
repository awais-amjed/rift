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

  /// Forget one entry — the message that carried it was deleted, so its
  /// plaintext should not outlive it in memory.
  void remove(String path) => _entries.remove(path);

  /// Forget everything held.
  ///
  /// This is the only place in the app where decrypted message content outlives
  /// the state of the cubit that fetched it, so it has to be emptied whenever
  /// the identity that could read it goes away — wiping the vault, or signing
  /// out of the central account. Everything here is re-downloadable, so the
  /// cost of clearing too eagerly is one round trip.
  void clear() => _entries.clear();
}
