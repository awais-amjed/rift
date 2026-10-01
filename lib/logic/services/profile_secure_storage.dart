import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// Seals bytes so only the person who sealed them can open them again — DPAPI
/// on Windows ([DpapiCodec]). Throws [FormatException] when bytes do not open.
abstract interface class SecretCodec {
  Uint8List seal(Uint8List plain);
  Uint8List open(Uint8List sealed);
}

/// Rift's secure storage on Windows: one profile's keys, sealed for the
/// signed-in Windows user, in a file in that profile's own folder under Local
/// AppData.
///
/// flutter_secure_storage keeps every app's values in one DPAPI file in the
/// *Roaming* AppData folder, and the place is fixed. Roaming AppData is copied
/// to every PC the person signs in to on a domain — the master seed with it —
/// which is the kind of syncing Rift's files were moved to Local AppData to
/// avoid. It was also one file for every profile, each rewriting the whole
/// thing. This keeps the same encryption and moves the file.
///
/// The first time a profile runs with this, it takes its own keys
/// ([legacyKeys]) out of the roaming file and deletes that file once nobody's
/// keys are left in it. A copy of its own that already exists is newer, so
/// whatever is still in the roaming file under its keys is dropped.
class ProfileSecureStorage extends FlutterSecureStoragePlatform {
  final File _file;
  final SecretCodec _codec;
  final File? _legacyFile;
  final Set<String> _legacyKeys;

  ProfileSecureStorage(
    this._file, {
    required SecretCodec codec,
    File? legacyFile,
    Set<String> legacyKeys = const {},
  }) : _codec = codec,
       _legacyFile = legacyFile,
       _legacyKeys = legacyKeys;

  Future<void> _tail = Future.value();
  Future<void>? _moving;

  /// One operation at a time, so a write never reads a map another write is
  /// about to replace.
  Future<T> _locked<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Once per run; a failure is tried again on the next operation rather than
  /// remembered.
  Future<void> _ensureMoved() async {
    try {
      await (_moving ??= _moveLegacy());
    } on FileSystemException {
      _moving = null;
      rethrow;
    }
  }

  Future<Map<String, String>> _load() async {
    await _ensureMoved();
    if (!await _file.exists()) return {};
    try {
      return _decode(await _file.readAsBytes());
    } on FormatException catch (e) {
      // Not deleted, as the plugin did: set aside, so the bytes are still
      // there for whoever can make sense of them. The app carries on as a
      // device with no vault, which a backup or recovery key restores.
      debugPrint('Secure storage unreadable ($e); set aside');
      await _file.rename('${_file.path}.unreadable');
      return {};
    }
  }

  Future<void> _moveLegacy() async {
    final legacy = _legacyFile;
    if (legacy == null || _legacyKeys.isEmpty || !await legacy.exists()) {
      return;
    }
    final Map<String, String> old;
    try {
      old = _decode(await legacy.readAsBytes());
    } on FormatException catch (e) {
      debugPrint('Old secure storage unreadable ($e); left in place');
      return;
    }
    final mine = {for (final key in _legacyKeys) key: ?old[key]};
    if (mine.isEmpty) return;
    if (!await _file.exists()) await _write(_file, mine);
    // Only now that this profile's copy is on disk does the roaming file lose
    // them. Another profile rewriting it at the same moment can put them
    // back; the next launch takes them out again.
    old.removeWhere((key, _) => mine.containsKey(key));
    try {
      if (old.isEmpty) {
        await legacy.delete();
      } else {
        await _write(legacy, old);
      }
    } on FileSystemException catch (e) {
      // This profile already has its copy; the next launch tries again.
      debugPrint('Old secure storage not cleaned up: $e');
    }
  }

  Map<String, String> _decode(Uint8List sealed) {
    final decoded = jsonDecode(utf8.decode(_codec.open(sealed)));
    if (decoded is! Map) throw const FormatException('Not a JSON object');
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (key is String && value is String) key: value,
    };
  }

  /// Through a temporary file and a rename: a crash mid-write leaves the old
  /// values rather than half of them. The plugin wrote in place.
  Future<void> _write(File file, Map<String, String> values) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final sealed = _codec.seal(utf8.encode(jsonEncode(values)));
    await temp.writeAsBytes(sealed, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _locked(() async => (await _load())[key]);

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _locked(() async => (await _load()).containsKey(key));

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _locked(_load);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => _locked(() async {
    final values = await _load();
    values[key] = value;
    await _write(_file, values);
  });

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _locked(() async {
    final values = await _load();
    if (values.remove(key) == null) return;
    await _write(_file, values);
  });

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _locked(() async {
        await _ensureMoved();
        if (await _file.exists()) await _file.delete();
      });
}
