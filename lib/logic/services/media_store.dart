import 'dart:async';
import 'dart:typed_data';

import '../../data/classes/media_entry.dart';

/// Pictures fetched from storage, by storage path, and where each fetch has
/// got to.
///
/// The one copy of every picture in the app. Widgets never read it: they read
/// `MediaCubit`, which mirrors it from [changes]. What *writes* it is the code
/// that fetches or uploads — the server cubit for avatars, the chat uploader
/// for attachments — which is why it sits below the cubits rather than inside
/// one. It replaced two caches that widgets looked into directly; a widget
/// whose fetch failed had no way to hear that another widget's had succeeded,
/// and kept showing initials over a picture that was sitting in memory.
///
/// Paths carry a random segment and change on every upload, so a held entry
/// is never stale — a new picture is a new key and the old one ages out.
/// Bounded by insertion order; anything evicted is re-downloadable.
class MediaStore {
  /// Avatars and directory icons.
  static final images = MediaStore(maxEntries: 120);

  /// Decrypted attachment bytes: a sender's own picks, stashed at upload so
  /// their message draws without a download, and a receiver's downloads.
  ///
  /// The only place decrypted message content outlives the cubit that fetched
  /// it, so it is [clear]ed whenever the identity that could read it goes —
  /// the vault wiped, the central account signed out.
  static final attachments = MediaStore(maxEntries: 80);

  final int maxEntries;

  MediaStore({required this.maxEntries});

  final Map<String, MediaEntry> _entries = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final StreamController<String> _changes = StreamController.broadcast();

  /// The path of every entry that changed, appeared or went away.
  Stream<String> get changes => _changes.stream;

  MediaEntry? operator [](String path) => _entries[path];

  /// Everything held, for a reader starting late.
  Map<String, MediaEntry> get snapshot => Map.unmodifiable(_entries);

  /// [path]'s bytes, fetched with [fetch] unless they are already here.
  ///
  /// Two callers asking for the same path share one fetch. A path that failed
  /// before is fetched again: callers decide how often to ask.
  Future<Uint8List?> load(String path, Future<Uint8List?> Function() fetch) {
    final held = _entries[path];
    if (held?.status == MediaStatus.success) return Future.value(held!.bytes);
    final running = _inFlight[path];
    if (running != null) return running;

    late final Future<Uint8List?> result;
    result = _fetch(fetch).then((bytes) {
      // Removed or cleared while it was on its way: the message was deleted
      // or the vault wiped, and its plaintext must not come back — to this
      // caller or to any that joined it.
      if (!identical(_inFlight[path], result)) return null;
      _inFlight.remove(path);
      if (bytes == null) {
        _set(path, const MediaEntry.failure());
      } else {
        put(path, bytes);
      }
      return bytes;
    });
    _inFlight[path] = result;
    _set(path, const MediaEntry.loading());
    return result;
  }

  static Future<Uint8List?> _fetch(Future<Uint8List?> Function() fetch) async {
    try {
      return await fetch();
    } catch (_) {
      return null;
    }
  }

  /// Hold [bytes] under [path] — an upload's own bytes, so they draw without
  /// downloading what was just sent.
  void put(String path, Uint8List bytes) =>
      _set(path, MediaEntry.success(bytes));

  /// Forget one entry: the message that carried it was deleted, and its
  /// plaintext should not outlive it in memory.
  void remove(String path) {
    _inFlight.remove(path);
    if (_entries.remove(path) != null) _changes.add(path);
  }

  /// Forget everything held, and every fetch on its way.
  void clear() {
    _inFlight.clear();
    final paths = _entries.keys.toList();
    _entries.clear();
    paths.forEach(_changes.add);
  }

  void _set(String path, MediaEntry entry) {
    // Re-inserted, so the newest is last and the oldest goes first.
    _entries.remove(path);
    _entries[path] = entry;
    _changes.add(path);
    while (_entries.length > maxEntries) {
      final oldest = _entries.keys.firstWhere(
        (p) => !_inFlight.containsKey(p),
        orElse: () => _entries.keys.first,
      );
      _entries.remove(oldest);
      _changes.add(oldest);
    }
  }
}
