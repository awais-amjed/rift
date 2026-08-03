import 'dart:typed_data';

/// In-memory cache of avatar bytes, keyed by storage path.
///
/// Avatars are re-rendered constantly (every message header, every member row)
/// so refetching per widget would hammer storage. Paths carry a random segment
/// and change on every upload, so a cached entry is never stale — a new picture
/// is a new key, and the old one simply ages out.
///
/// Bounded by insertion order; anything evicted is re-downloadable.
class AvatarCache {
  AvatarCache._();
  static final AvatarCache instance = AvatarCache._();

  static const int _maxEntries = 120;
  final Map<String, Uint8List> _entries = <String, Uint8List>{};

  Uint8List? get(String path) => _entries[path];

  void put(String path, Uint8List bytes) {
    _entries.remove(path);
    _entries[path] = bytes;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}
