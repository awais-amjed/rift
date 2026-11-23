import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'media_disk_cache.dart';
import 'storage_namespace.dart';

/// Clips kept on disk between sessions, so a soundboard is instant the second
/// time somebody presses it.
///
/// Safe to keep forever, and that is a property of the path rather than a
/// bet: an object name is minted once and the server has no UPDATE grant on
/// the column that holds it, so bytes under a path can never change. A clip
/// that is deleted simply stops being asked for.
///
/// Swept by age rather than bounded by count. A server can hold at most
/// `app.soundboard_max()` clips of `SoundboardRepository.maxBytes`, so the
/// ceiling is 240 MB per server — the thing worth cleaning up is not a full
/// board but the boards of servers this device has not opened in a long
/// time. That worst case is ten times what it was when a clip was capped at
/// 512 KB, which is what turns the 30-day sweep from tidiness into the
/// thing keeping a phone's disk honest.
///
/// Held under the server's host as well as the path, and on disk under a
/// hash of both ([MediaDiskCache.fileNameFor]). The path is the server's
/// choice: built into a file name, a `..\` in it reached out of the folder on
/// Windows, so a server could have a listener's client delete or write a file
/// of its choosing, and one server could pre-seed another's clip.
class SoundboardCache {
  SoundboardCache._();
  static final SoundboardCache instance = SoundboardCache._();

  /// How long a clip nobody has played survives on disk.
  static const Duration _keepFor = Duration(days: 30);

  /// Web has no file to hand `audioplayers`, so it plays from memory. Bounded,
  /// because this one really is a cache and not a directory.
  static const int _maxWebEntries = 40;

  final Map<String, String> _files = {};
  final Map<String, Uint8List> _bytes = {};

  /// One fetch per clip at a time: two presses of a clip nobody has heard
  /// downloaded it twice and wrote the file under the first one playing it.
  final Map<String, Future<Source?>> _loading = {};
  Directory? _dir;
  bool _swept = false;

  static String _keyOf(String origin, String objectPath) =>
      '$origin\n$objectPath';

  /// Something `audioplayers` can play: the clip at [objectPath] on [origin]
  /// (the server's address), fetched through [fetch] the first time. Null
  /// when the fetch fails — the caller stays silent rather than guessing.
  Future<Source?> source(
    String origin,
    String objectPath,
    Future<Uint8List?> Function() fetch,
  ) async {
    final key = _keyOf(origin, objectPath);
    if (kIsWeb) {
      final held = _bytes[key];
      if (held != null) return BytesSource(held);
      final bytes = await fetch();
      if (bytes == null) return null;
      _remember(key, bytes);
      return BytesSource(bytes);
    }

    final known = _files[key];
    // Asked again rather than trusted: a temp cleaner can take the file
    // between two presses, and a stale entry was silence until a restart.
    if (known != null && await File(known).exists()) {
      return DeviceFileSource(known);
    }
    _files.remove(key);

    final loading = _loading[key];
    if (loading != null) return loading;
    final load = _load(key, origin, objectPath, fetch);
    _loading[key] = load;
    try {
      return await load;
    } finally {
      // Removed, not awaited: it is [load], awaited just above.
      if (identical(_loading[key], load)) unawaited(_loading.remove(key));
    }
  }

  Future<Source?> _load(
    String key,
    String origin,
    String objectPath,
    Future<Uint8List?> Function() fetch,
  ) async {
    final file = await _fileFor(origin, objectPath);
    if (file == null) return null;
    if (await file.exists()) {
      _files[key] = file.path;
      // Touched, so the sweep reads it as recently used rather than as old.
      unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
      return DeviceFileSource(file.path);
    }

    final bytes = await fetch();
    if (bytes == null) return null;
    // No disk to write to is not a reason not to play it.
    if (!await _write(file, bytes)) return BytesSource(bytes);
    _files[key] = file.path;
    return DeviceFileSource(file.path);
  }

  /// Put bytes the caller already holds into the cache without a fetch — the
  /// uploader's own copy, so their first press is not a download of what they
  /// just sent.
  Future<void> warm(String origin, String objectPath, Uint8List bytes) async {
    final key = _keyOf(origin, objectPath);
    if (kIsWeb) {
      _remember(key, bytes);
      return;
    }
    final file = await _fileFor(origin, objectPath);
    if (file == null) return;
    // A cache that could not be written is a download later, not a failure.
    if (await _write(file, bytes)) _files[key] = file.path;
  }

  /// Written beside and renamed into place, so a write cut short — a full
  /// disk, Rift quit halfway — never leaves a part of a clip under its name,
  /// which every later press would have trusted and kept fresh past the
  /// sweep.
  static Future<bool> _write(File file, Uint8List bytes) async {
    final part = File('${file.path}.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      return true;
    } catch (_) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Drop a clip that has been deleted from the server.
  ///
  /// The path is *derived*, not looked up. `_files` only knows about clips
  /// this run has played, so consulting it meant a clip deleted after a
  /// restart — or deleted on a device that had the file but had not pressed
  /// it since launch — was forgotten from a map and left on disk. Which is
  /// every case that matters: the common one is somebody tidying up a
  /// soundboard days after anyone last used it.
  Future<void> forget(String origin, String objectPath) async {
    final key = _keyOf(origin, objectPath);
    _bytes.remove(key);
    _files.remove(key);
    if (kIsWeb) return;
    final file = await _fileFor(origin, objectPath);
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Already gone, or not ours to delete.
    }
  }

  void _remember(String key, Uint8List bytes) {
    _bytes.remove(key);
    _bytes[key] = bytes;
    while (_bytes.length > _maxWebEntries) {
      _bytes.remove(_bytes.keys.first);
    }
  }

  /// `<cache>/rift_soundboard[_<profile>]/<hash of host and path>`.
  ///
  /// The app's own cache folder, not the temporary one: on Linux that is
  /// `/tmp`, shared by every account on the machine, where another one could
  /// make the folder first, read which servers you are on from its names, or
  /// leave you unable to write and so hearing nothing. Namespaced like
  /// everything else this app writes, so two profiles running side by side
  /// do not share a directory — see [StorageNamespace].
  Future<File?> _fileFor(String origin, String objectPath) async {
    try {
      final suffix = StorageNamespace.apply();
      final dir = _dir ??= Directory(
        '${(await getApplicationCacheDirectory()).path}/rift_soundboard'
        '${suffix.isEmpty ? '' : '_$suffix'}',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      if (!_swept) {
        _swept = true;
        unawaited(_sweep(dir));
      }
      final name = await MediaDiskCache.fileNameFor(origin, objectPath);
      return File('${dir.path}/$name');
    } catch (_) {
      return null;
    }
  }

  Future<void> _sweep(Directory dir) async {
    final cutoff = DateTime.now().subtract(_keepFor);
    try {
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final stat = await entry.stat();
        // A `.part` is a write that never finished, from a run that ended.
        if (entry.path.endsWith('.part') || stat.modified.isBefore(cutoff)) {
          await entry.delete();
        }
      }
    } catch (_) {
      // A sweep that cannot run costs disk, not correctness.
    }
  }
}
