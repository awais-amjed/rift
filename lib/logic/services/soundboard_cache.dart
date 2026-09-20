import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
  Directory? _dir;
  bool _swept = false;

  /// Something `audioplayers` can play, fetching [objectPath] through [fetch]
  /// the first time. Null when the fetch fails — the caller stays silent
  /// rather than guessing.
  Future<Source?> source(
    String objectPath,
    Future<Uint8List?> Function() fetch,
  ) async {
    if (kIsWeb) {
      final held = _bytes[objectPath];
      if (held != null) return BytesSource(held);
      final bytes = await fetch();
      if (bytes == null) return null;
      _remember(objectPath, bytes);
      return BytesSource(bytes);
    }

    final known = _files[objectPath];
    if (known != null) return DeviceFileSource(known);

    final file = await _fileFor(objectPath);
    if (file == null) return null;
    if (await file.exists()) {
      _files[objectPath] = file.path;
      // Touched, so the sweep reads it as recently used rather than as old.
      unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
      return DeviceFileSource(file.path);
    }

    final bytes = await fetch();
    if (bytes == null) return null;
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // No disk to write to is not a reason not to play it.
      return BytesSource(bytes);
    }
    _files[objectPath] = file.path;
    return DeviceFileSource(file.path);
  }

  /// Put bytes the caller already holds into the cache without a fetch — the
  /// uploader's own copy, so their first press is not a download of what they
  /// just sent.
  Future<void> warm(String objectPath, Uint8List bytes) async {
    if (kIsWeb) {
      _remember(objectPath, bytes);
      return;
    }
    final file = await _fileFor(objectPath);
    if (file == null) return;
    try {
      await file.writeAsBytes(bytes, flush: true);
      _files[objectPath] = file.path;
    } catch (_) {
      // A cache that could not be written is a download later, not a failure.
    }
  }

  /// Drop a clip that has been deleted from the server.
  Future<void> forget(String objectPath) async {
    _bytes.remove(objectPath);
    final path = _files.remove(objectPath);
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone, or not ours to delete.
    }
  }

  void _remember(String objectPath, Uint8List bytes) {
    _bytes.remove(objectPath);
    _bytes[objectPath] = bytes;
    while (_bytes.length > _maxWebEntries) {
      _bytes.remove(_bytes.keys.first);
    }
  }

  /// `<temp>/rift_soundboard[_<profile>]/<flattened object path>`.
  ///
  /// Namespaced like everything else this app writes, so two profiles running
  /// side by side on one machine do not share a directory — see
  /// [StorageNamespace].
  Future<File?> _fileFor(String objectPath) async {
    try {
      final suffix = StorageNamespace.apply();
      final dir = _dir ??= Directory(
        '${(await getTemporaryDirectory()).path}/rift_soundboard'
        '${suffix.isEmpty ? '' : '_$suffix'}',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      if (!_swept) {
        _swept = true;
        unawaited(_sweep(dir));
      }
      return File('${dir.path}/${objectPath.replaceAll('/', '_')}');
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
        if (stat.modified.isBefore(cutoff)) await entry.delete();
      }
    } catch (_) {
      // A sweep that cannot run costs disk, not correctness.
    }
  }
}
