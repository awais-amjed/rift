import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/classes/call_clip_audio.dart';
import '../../../data/classes/stored_clip.dart';
import '../../helper_methods.dart';
import '../storage_namespace.dart';

/// The clips of calls this device keeps: the newest [keep], so one closed
/// unsaved can be opened again (CALLS.md, *Clipping a call*).
///
/// A clip is the decrypted sound of an end-to-end encrypted call, other
/// people's voices, so it is kept exactly as the saved conversations are
/// (`MessageCache`): sealed with AES-256-GCM under a key derived from the
/// seed ([CryptoRepository.deriveClipKey]), on the Rust cipher off the UI
/// thread. Two files a clip, both sealed: `<id>.meta`, small, which the list
/// is read from, and `<id>.pcm`, the samples, opened only with the clip. A
/// copy the key cannot open is another account's, or damaged, and is deleted
/// when found. The folder goes with the account (`VaultCubit.resetVault`).
///
/// One thing at a time, in the order asked, so a delete never meets a write
/// half done; each file is written beside and moved over.
class ClipLibrary {
  /// How many are kept. The eleventh takes the oldest's place.
  static const int keep = 10;

  static const int _version = 1;
  static const int _ivLength = 12;

  static final ClipLibrary instance = ClipLibrary();

  final Future<Directory> Function() _root;
  final CryptoRepository _crypto;
  final StreamController<void> _changes = StreamController.broadcast();
  Future<void> _turn = Future.value();

  Uint8List? _key;
  String? _keySeed;

  ClipLibrary({Future<Directory> Function()? root, CryptoRepository? crypto})
    : _root = root ?? _defaultRoot,
      _crypto = crypto ?? CryptoRepository();

  /// Rings after each add, delete or clear.
  Stream<void> get changes => _changes.stream;

  /// Keeps [audio], and drops whatever falls past the newest [keep].
  Future<StoredClip> add(
    String seed,
    CallClipAudio audio, {
    required String? serverId,
    required String? channelId,
    required String place,
    required bool fromDmCall,
  }) => _inTurn(() async {
    final dir = await _dir();
    var micros = audio.at.toUtc().microsecondsSinceEpoch;
    while (File('${dir.path}/$micros.meta').existsSync()) {
      micros++;
    }
    final clip = StoredClip(
      id: '$micros',
      at: audio.at.toUtc(),
      rate: audio.rate,
      channels: audio.channels,
      frames: audio.frames,
      serverId: serverId,
      channelId: channelId,
      place: place,
      fromDmCall: fromDmCall,
    );
    final key = await _keyFor(seed);
    final pcm = audio.pcm.buffer.asUint8List(
      audio.pcm.offsetInBytes,
      audio.pcm.lengthInBytes,
    );
    await _write(_pcmFile(dir, clip.id), await _seal(pcm, key));
    await _write(
      _metaFile(dir, clip.id),
      await _seal(
        Uint8List.fromList(
          utf8.encode(jsonEncode({'v': _version, 'clip': clip.toJson()})),
        ),
        key,
      ),
    );
    final ids = _ids(dir);
    for (final old in ids.skip(keep)) {
      _remove(dir, old);
    }
    _changes.add(null);
    return clip;
  });

  /// What is kept, newest first. Opens only the small files.
  Future<List<StoredClip>> list(String seed) => _inTurn(() async {
    final dir = await _dir();
    final key = await _keyFor(seed);
    final clips = <StoredClip>[];
    for (final id in _ids(dir)) {
      try {
        final opened = await _open(_metaFile(dir, id).readAsBytesSync(), key);
        final json = jsonDecode(utf8.decode(opened));
        if (json is! Map<String, dynamic> || json['v'] != _version) {
          throw const FormatException('not a clip');
        }
        clips.add(StoredClip.fromJson(json['clip'] as Map<String, dynamic>));
      } catch (e) {
        // The type only: never what it held.
        HelperMethods.printDebug(
          '[Clips] dropped an unreadable clip: ${e.runtimeType}',
        );
        _remove(dir, id);
      }
    }
    return clips;
  });

  /// The sound of [clip], or null when it is gone or will not open.
  Future<CallClipAudio?> load(String seed, StoredClip clip) =>
      _inTurn(() async {
        final dir = await _dir();
        final file = _pcmFile(dir, clip.id);
        if (!file.existsSync()) return null;
        try {
          final opened = await _open(
            await file.readAsBytes(),
            await _keyFor(seed),
          );
          // A view needs an even start; a copy is made only if it is not.
          final bytes = opened.offsetInBytes.isEven
              ? opened
              : Uint8List.fromList(opened);
          return CallClipAudio(
            id: clip.id.hashCode,
            pcm: bytes.buffer.asInt16List(
              bytes.offsetInBytes,
              bytes.lengthInBytes ~/ 2,
            ),
            rate: clip.rate,
            channels: clip.channels,
            // Local, as a press's own time is: the trim view prints it and
            // names the saved file by it.
            at: clip.at.toLocal(),
          );
        } catch (e) {
          HelperMethods.printDebug(
            '[Clips] a clip would not open: ${e.runtimeType}',
          );
          return null;
        }
      });

  Future<void> delete(String id) => _inTurn(() async {
    _remove(await _dir(), id);
    _changes.add(null);
  });

  /// Every clip, for good: the account is leaving this device, or the person
  /// asked.
  Future<void> clear() => _inTurn(() async {
    if (kIsWeb) return;
    final dir = await _root();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _changes.add(null);
  });

  // ── Files ─────────────────────────────────────────────────────────────

  Future<Directory> _dir() async {
    final dir = await _root();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  File _metaFile(Directory dir, String id) => File('${dir.path}/$id.meta');
  File _pcmFile(Directory dir, String id) => File('${dir.path}/$id.pcm');

  /// Every clip's id, newest first. A clip is there when its small file is;
  /// samples without one were left by a write cut short, and go.
  List<String> _ids(Directory dir) {
    final metas = <String>{};
    final pcms = <String>{};
    for (final entry in dir.listSync().whereType<File>()) {
      final name = entry.uri.pathSegments.last;
      if (name.endsWith('.meta')) metas.add(name.substring(0, name.length - 5));
      if (name.endsWith('.pcm')) pcms.add(name.substring(0, name.length - 4));
    }
    for (final orphan in pcms.difference(metas)) {
      _remove(dir, orphan);
    }
    return metas.toList()
      ..sort((a, b) => (int.tryParse(b) ?? 0).compareTo(int.tryParse(a) ?? 0));
  }

  void _remove(Directory dir, String id) {
    for (final file in [_metaFile(dir, id), _pcmFile(dir, id)]) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (e) {
        HelperMethods.printDebug('[Clips] could not delete a clip: $e');
      }
    }
  }

  /// Writes [sealed] as its nonce, then its ciphertext: in two pieces,
  /// since a two-minute clip is 23 MB and joining them would copy it.
  Future<void> _write(
    File file,
    ({Uint8List ciphertext, Uint8List iv}) sealed,
  ) async {
    final pending = File('${file.path}.tmp');
    final sink = pending.openWrite();
    sink
      ..add(sealed.iv)
      ..add(sealed.ciphertext);
    await sink.flush();
    await sink.close();
    await pending.rename(file.path);
  }

  // ── Sealing ───────────────────────────────────────────────────────────

  Future<({Uint8List ciphertext, Uint8List iv})> _seal(
    Uint8List data,
    Uint8List key,
  ) => _crypto.encryptBytes(data: data, key: key);

  Future<Uint8List> _open(Uint8List bytes, Uint8List key) {
    if (bytes.length <= _ivLength) {
      throw const FormatException('too short');
    }
    return _crypto.decryptBytes(
      ciphertext: Uint8List.sublistView(bytes, _ivLength),
      key: key,
      iv: Uint8List.sublistView(bytes, 0, _ivLength),
    );
  }

  Future<Uint8List> _keyFor(String seed) async {
    final held = _key;
    if (held != null && _keySeed == seed) return held;
    final key = await _crypto.deriveClipKey(CryptoRepository.fromBase64(seed));
    _keySeed = seed;
    _key = key;
    return key;
  }

  Future<T> _inTurn<T>(Future<T> Function() work) {
    final result = _turn.then((_) => work());
    _turn = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  static Future<Directory> _defaultRoot() async => Directory(
    '${await StorageNamespace.profileDirectory(StorageNamespace.apply())}'
    '/clips',
  );
}
