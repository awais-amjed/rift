import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_namespace.dart';

/// The pictures `MediaStore.images` fetched, kept on disk between runs, so a
/// restart draws avatars and icons without downloading every one again.
///
/// Kept without ever asking whether a picture changed, for the reason the
/// store's own copy is: a path carries a random segment and changes on every
/// upload, so the bytes under a path never do. A new picture is a new name,
/// and the old file ages out.
///
/// Keyed by the host the picture came from as well as its path. A path is
/// chosen by whoever runs the server that names it, so a server repeating
/// another's path could otherwise leave its own bytes on disk under it, to be
/// drawn as the other server's member on every run after.
///
/// Pictures only, never attachments: those are decrypted message content, and
/// nothing of a message is written to disk unsealed (`MessageCache` is the
/// sealed exception). A picture here is one the server's members can all see,
/// but together they say whom this device has seen, so [clear] runs with the
/// vault wipe.
///
/// Bounded by size, least recently drawn first, and anything not drawn for
/// [_keepFor] goes, so the pictures of a server left long ago stop taking up
/// room.
class MediaDiskCache {
  final Future<Directory> Function() _root;

  /// The most the folder holds after a sweep. An avatar is at most
  /// `AvatarImage.maxDimension` square, tens of kilobytes, so this is
  /// hundreds of people.
  final int maxBytes;

  MediaDiskCache({
    Future<Directory> Function()? root,
    this.maxBytes = 64 * 1024 * 1024,
  }) : _root = root ?? _defaultRoot;

  /// How long a picture nobody has drawn survives on disk.
  static const Duration _keepFor = Duration(days: 30);

  /// Written since the last sweep. Past a quarter of [maxBytes] the folder is
  /// swept again, so a long session cannot grow it without bound.
  int _writtenSinceSweep = 0;
  bool _swept = false;
  Directory? _dir;

  /// The end of the queue every operation joins, so a [clear] is not undone
  /// by a write that was already on its way.
  Future<void> _last = Future.value();

  /// The bytes saved for [path] from [origin], or null when there are none.
  /// Never throws: a file that cannot be read is a download, not a failure.
  Future<Uint8List?> read(String origin, String path) {
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      if (!_swept) await _sweep();
      try {
        final file = await _fileFor(origin, path);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return null;
        try {
          // Touched, so the sweep reads it as recently drawn, not old.
          await file.setLastModified(DateTime.now());
        } catch (_) {
          // Kept a little less long, still drawn now.
        }
        return bytes;
      } catch (_) {
        return null;
      }
    });
  }

  /// Save [bytes] for [path] from [origin].
  Future<void> write(String origin, String path, Uint8List bytes) {
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      try {
        final file = await _fileFor(origin, path);
        await file.parent.create(recursive: true);
        // Renamed into place, so a run killed mid-write leaves no half a
        // picture to be drawn broken from then on.
        final partial = File('${file.path}.part');
        await partial.writeAsBytes(bytes, flush: true);
        await partial.rename(file.path);
        _writtenSinceSweep += bytes.length;
        if (!_swept || _writtenSinceSweep > maxBytes ~/ 4) await _sweep();
      } catch (_) {
        // A picture that could not be saved is a download next run.
      }
    });
  }

  /// Delete everything saved: the identity that saw these people is going.
  Future<void> clear() {
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      try {
        final root = await _rootDir();
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {
        // Already gone.
      }
      _writtenSinceSweep = 0;
    });
  }

  Future<void> _sweep() async {
    _swept = true;
    _writtenSinceSweep = 0;
    try {
      final root = await _rootDir();
      if (!await root.exists()) return;
      final cutoff = DateTime.now().subtract(_keepFor);
      final kept = <({File file, DateTime used, int size})>[];
      await for (final entry in root.list()) {
        if (entry is! File) continue;
        final stat = await entry.stat();
        if (entry.path.endsWith('.part') || stat.modified.isBefore(cutoff)) {
          await entry.delete();
        } else {
          kept.add((file: entry, used: stat.modified, size: stat.size));
        }
      }
      var total = kept.fold<int>(0, (sum, f) => sum + f.size);
      kept.sort((a, b) => a.used.compareTo(b.used));
      for (final f in kept) {
        if (total <= maxBytes) break;
        await f.file.delete();
        total -= f.size;
      }
    } catch (_) {
      // A sweep that cannot run costs disk, not correctness.
    }
  }

  Future<T> _inTurn<T>(Future<T> Function() work) {
    final result = _last.then((_) => work());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// A name that cannot hold a separator or say where the picture came from
  /// at a glance: the SHA-256 of the host and the path.
  Future<File> _fileFor(String origin, String path) async {
    final digest = await Sha256().hash(utf8.encode('$origin\n$path'));
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return File('${(await _rootDir()).path}/$hex');
  }

  Future<Directory> _rootDir() async => _dir ??= await _root();

  /// `<cache>/rift_pictures[_<profile>]`, namespaced like everything else the
  /// app writes (see [StorageNamespace]). The cache folder rather than the
  /// profile's own, since the OS may empty it and nothing here is lost when
  /// it does.
  static Future<Directory> _defaultRoot() async {
    final suffix = StorageNamespace.apply();
    return Directory(
      '${(await getApplicationCacheDirectory()).path}/rift_pictures'
      '${suffix.isEmpty ? '' : '_$suffix'}',
    );
  }
}
