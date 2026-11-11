import 'dart:async';
import 'dart:typed_data';

import '../../data/classes/media_entry.dart';
import 'media_disk_cache.dart';

/// Pictures fetched from storage, by host and storage path, and where each
/// fetch has got to.
///
/// The one copy of every picture in the app. Widgets never read it: they read
/// `MediaCubit`, which mirrors it from [changes]. What *writes* it is the code
/// that fetches or uploads — `ProfileApi` for avatars, the chat uploader
/// for attachments — which is why it sits below the cubits rather than inside
/// one. It replaced two caches that widgets looked into directly; a widget
/// whose fetch failed had no way to hear that another widget's had succeeded,
/// and kept showing initials over a picture that was sitting in memory.
///
/// Paths carry a random segment and change on every upload, so a held entry
/// is never stale — a new picture is a new key and the old one ages out.
/// Bounded by insertion order; anything evicted is re-downloadable.
///
/// An entry is held under [keyOf] its host and path, not the path alone. A
/// path is chosen by whoever runs the server that names it, so a server
/// repeating another's path — a member's avatar, or its id and icon — would
/// otherwise have its own bytes drawn in the other's place for the rest of
/// the run.
class MediaStore {
  /// Avatars and server and directory icons, also kept on disk between runs
  /// ([MediaDiskCache]).
  static final images = MediaStore(maxEntries: 120, disk: MediaDiskCache());

  /// Decrypted attachment bytes: a sender's own picks, stashed at upload so
  /// their message draws without a download, and a receiver's downloads.
  ///
  /// The only place decrypted message content outlives the cubit that fetched
  /// it, so it is [clear]ed whenever the identity that could read it goes —
  /// the vault wiped, the central account signed out.
  static final attachments = MediaStore(maxEntries: 80);

  final int maxEntries;

  /// Where fetched bytes are also kept between runs. Never for attachments,
  /// which are decrypted message content.
  final MediaDiskCache? _disk;

  MediaStore({required this.maxEntries, MediaDiskCache? disk}) : _disk = disk;

  final Map<String, MediaEntry> _entries = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final StreamController<String> _changes = StreamController.broadcast();

  /// The key of every entry that changed, appeared or went away.
  Stream<String> get changes => _changes.stream;

  /// What an entry is held under: [path] on [origin], the host it is fetched
  /// from. An attachment has none, its path naming a channel's own blob. A
  /// host cannot hold a line break, so no two pairs make one key.
  static String keyOf(String? origin, String path) =>
      origin == null ? path : '$origin\n$path';

  MediaEntry? operator [](String key) => _entries[key];

  /// Everything held, for a reader starting late.
  Map<String, MediaEntry> get snapshot => Map.unmodifiable(_entries);

  /// [path]'s bytes, fetched with [fetch] unless they are already here.
  ///
  /// Two callers asking for the same path share one fetch. A path that failed
  /// before is fetched again: callers decide how often to ask.
  ///
  /// [origin] is the host [path] is on, which the entry is held under here
  /// and on disk ([keyOf]). Without it nothing is read from or saved to disk.
  Future<Uint8List?> load(
    String path,
    Future<Uint8List?> Function() fetch, {
    String? origin,
  }) {
    final key = keyOf(origin, path);
    final held = _entries[key];
    if (held?.status == MediaStatus.success) return Future.value(held!.bytes);
    final running = _inFlight[key];
    if (running != null) return running;

    final disk = origin == null ? null : _disk;
    var saved = false;
    Future<Uint8List?> savedOrFetched() async {
      final kept = await disk?.read(origin!, path);
      if (kept == null) return fetch();
      saved = true;
      return kept;
    }

    late final Future<Uint8List?> result;
    result = _fetch(savedOrFetched).then((bytes) {
      // Removed or cleared while it was on its way: the message was deleted
      // or the vault wiped, and its plaintext must not come back — to this
      // caller or to any that joined it.
      if (!identical(_inFlight[key], result)) return null;
      _inFlight.remove(key);
      if (bytes == null) {
        _set(key, const MediaEntry.failure());
      } else {
        _set(key, MediaEntry.success(bytes));
        if (!saved && disk != null) unawaited(disk.write(origin!, path, bytes));
      }
      return bytes;
    });
    _inFlight[key] = result;
    _set(key, const MediaEntry.loading());
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
  /// downloading what was just sent, this run or the next. [origin] as for
  /// [load].
  void put(String path, Uint8List bytes, {String? origin}) {
    _set(keyOf(origin, path), MediaEntry.success(bytes));
    final disk = _disk;
    if (origin != null && disk != null) {
      unawaited(disk.write(origin, path, bytes));
    }
  }

  /// Forget one attachment: the message that carried it was deleted, and its
  /// plaintext should not outlive it in memory.
  void remove(String path) {
    _inFlight.remove(path);
    if (_entries.remove(path) != null) _changes.add(path);
  }

  /// Forget everything held, every fetch on its way, and what is on disk.
  Future<void> clear() {
    _inFlight.clear();
    final keys = _entries.keys.toList();
    _entries.clear();
    keys.forEach(_changes.add);
    return _disk?.clear() ?? Future.value();
  }

  void _set(String key, MediaEntry entry) {
    // Re-inserted, so the newest is last and the oldest goes first.
    _entries.remove(key);
    _entries[key] = entry;
    _changes.add(key);
    while (_entries.length > maxEntries) {
      final oldest = _entries.keys.firstWhere(
        (k) => !_inFlight.containsKey(k),
        orElse: () => _entries.keys.first,
      );
      _entries.remove(oldest);
      _changes.add(oldest);
    }
  }
}
