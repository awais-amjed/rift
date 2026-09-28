import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:rift_crypto/rift_crypto.dart';

import '../../data/classes/message_cache_slot.dart';
import '../helper_methods.dart';
import 'storage_namespace.dart';

/// Over the helper budget and one job: the one place the saved conversations
/// touch the disk; the ordering rules below are why it is one file.
///
/// Conversations kept on this device, so one opens with its last page drawn
/// instead of a spinner while the server is asked.
///
/// **A head start, never the answer.** Every open still fetches the newest
/// page and replaces what was drawn from here, because a saved copy cannot
/// know what was deleted, edited or reacted to since. What this buys is the
/// wait, and reading a conversation with no connection at all.
///
/// Sealed as a whole with a key derived from the master seed
/// ([CryptoRepository.deriveMessageCacheKey]), so it is exactly as readable
/// as the seed already is: a device that can open these could open the
/// conversations themselves. Sealing the whole file rather than relying on
/// the rows inside being ciphertext matters — a webhook's message and every
/// author name and time are in the clear on the row.
///
/// Wiped with the identity that could read it: a vault reset, leaving a
/// server, signing out of central. Not on the web, whose storage is the
/// browser's rather than the platform's secure store.
///
/// **Wiped means staying wiped.** The chat cubits save the open conversation
/// when they notice it closing — and leaving a server is exactly what makes
/// them notice, a moment *after* the wipe. So every operation runs in the
/// order it was asked for, and a wipe shuts its scope (or, for [clear], the
/// seed) to writes asked for after it. [reopenScope] lets a rejoined server
/// or a signed-in account save again.
class MessageCache {
  final CryptoRepository _crypto;
  final Future<Directory> Function() _root;

  MessageCache({CryptoRepository? crypto, Future<Directory> Function()? root})
    : _crypto = crypto ?? CryptoRepository(),
      _root = root ?? _defaultRoot;

  static final MessageCache instance = MessageCache();

  /// Bumped when the shape of a saved file changes; an older one is ignored
  /// and replaced on the next save.
  static const int _version = 1;

  static const int _ivLength = 12;

  /// Hex characters kept from each HMAC for a file or folder name — 128 bits,
  /// which is plenty to keep names apart and says nothing about what they are.
  static const int _nameLength = 32;

  String? _keySeed;
  Uint8List? _key;

  /// Scopes wiped this run, and seeds whose identity was — see the class
  /// comment. Writes to either are dropped.
  final Set<String> _shutScopes = {};
  final Set<String> _retiredSeeds = {};

  /// The end of the queue every operation joins.
  Future<void> _last = Future.value();

  /// What was saved for [slot], or null when nothing was, it cannot be
  /// opened, or it belongs to another conversation. Never throws: a copy that
  /// cannot be read is a spinner, not a failure.
  Future<Map<String, dynamic>?> read(String seed, MessageCacheSlot slot) {
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      if (_retiredSeeds.contains(seed)) return null;
      try {
        final file = await _fileFor(seed, slot);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        if (bytes.length <= _ivLength) return null;
        final clear = await _crypto.decryptBytes(
          ciphertext: bytes.sublist(_ivLength),
          key: await _keyFor(seed),
          iv: bytes.sublist(0, _ivLength),
        );
        final json = jsonDecode(utf8.decode(clear));
        if (json is! Map<String, dynamic>) return null;
        if (json['v'] != _version || json['slot'] != slot.label) return null;
        final data = json['data'];
        return data is Map<String, dynamic> ? data : null;
      } catch (e) {
        // The type only: a decode error quotes the text it choked on, which
        // is the decrypted copy.
        HelperMethods.printDebug(
          '[MessageCache] unreadable copy: ${e.runtimeType}',
        );
        return null;
      }
    });
  }

  /// Replace what is saved for [slot]. Written beside the old copy and moved
  /// over it, so a crash mid-write leaves the previous copy rather than half
  /// of a new one.
  Future<void> write(
    String seed,
    MessageCacheSlot slot,
    Map<String, dynamic> data,
  ) {
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      // Asked in turn, not when called: a wipe queued ahead of this write
      // may shut the door between the two.
      if (_refuses(seed, slot.scope)) return;
      try {
        final sealed = await _crypto.encryptBytes(
          data: utf8.encode(
            jsonEncode({'v': _version, 'slot': slot.label, 'data': data}),
          ),
          key: await _keyFor(seed),
        );
        final file = await _fileFor(seed, slot);
        await file.parent.create(recursive: true);
        final pending = File('${file.path}.tmp');
        await pending.writeAsBytes([
          ...sealed.iv,
          ...sealed.ciphertext,
        ], flush: true);
        await pending.rename(file.path);
      } catch (e) {
        HelperMethods.printDebug('[MessageCache] save failed: $e');
      }
    });
  }

  /// Delete the copy for one conversation — this device lost it.
  Future<void> forget(String seed, MessageCacheSlot slot) {
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      try {
        final file = await _fileFor(seed, slot);
        if (await file.exists()) await file.delete();
      } catch (e) {
        HelperMethods.printDebug('[MessageCache] forget failed: $e');
      }
    });
  }

  /// Delete every copy under [scope] — a server left, or central signed out
  /// of — and save nothing more there until [reopenScope]. See
  /// [MessageCacheSlot.scopesOfServer] and [MessageCacheSlot.centralScope].
  Future<void> forgetScope(String seed, String scope) {
    _shutScopes.add(scope);
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      try {
        final dir = await _scopeDir(seed, scope);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        HelperMethods.printDebug('[MessageCache] forget scope failed: $e');
      }
    });
  }

  /// Let [scope] be saved to again — the server was joined again, or the
  /// account signed back in.
  void reopenScope(String scope) => _shutScopes.remove(scope);

  /// Delete every copy under [scope] except [keep] — the channels a server
  /// still lists. A channel deleted, or a private one this member was taken
  /// out of, stops being listed, and its copy goes with it.
  Future<void> keepOnly(
    String seed,
    String scope,
    Iterable<MessageCacheSlot> keep,
  ) {
    if (kIsWeb) return Future.value();
    final slots = keep.toList();
    return _inTurn(() async {
      try {
        final dir = await _scopeDir(seed, scope);
        if (!await dir.exists()) return;
        // By name, not full path: `_fileFor` joins with '/', and on Windows
        // `list()` hands back the same file joined with '\', so comparing
        // paths matched nothing and deleted every copy in the scope.
        final wanted = {
          for (final slot in slots)
            p.basename((await _fileFor(seed, slot)).path),
        };
        await for (final entry in dir.list()) {
          if (entry is File && !wanted.contains(p.basename(entry.path))) {
            await entry.delete();
          }
        }
      } catch (e) {
        HelperMethods.printDebug('[MessageCache] prune failed: $e');
      }
    });
  }

  /// Delete everything, whatever seed wrote it, and save nothing more under
  /// the seed in use. For a vault reset, where the identity is going away and
  /// nothing it saved should outlive it.
  Future<void> clear() {
    final seed = _keySeed;
    if (seed != null) _retiredSeeds.add(seed);
    _keySeed = null;
    _key = null;
    if (kIsWeb) return Future.value();
    return _inTurn(() async {
      try {
        final root = await _root();
        if (await root.exists()) await root.delete(recursive: true);
      } catch (e) {
        HelperMethods.printDebug('[MessageCache] clear failed: $e');
      }
    });
  }

  bool _refuses(String seed, String scope) =>
      _retiredSeeds.contains(seed) || _shutScopes.contains(scope);

  /// Run [op] after everything asked for before it.
  Future<T> _inTurn<T>(Future<T> Function() op) {
    final result = _last.then((_) => op());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  // ── Names ────────────────────────────────────────────────

  Future<File> _fileFor(String seed, MessageCacheSlot slot) async {
    final dir = await _scopeDir(seed, slot.scope);
    final name = await _name(seed, 'slot:${slot.label}');
    return File('${dir.path}/$name.bin');
  }

  Future<Directory> _scopeDir(String seed, String scope) async {
    final root = await _root();
    return Directory('${root.path}/${await _name(seed, 'scope:$scope')}');
  }

  /// A name that does not say what it names: an HMAC under the cache key, so
  /// it cannot be confirmed by guessing a server's address either.
  Future<String> _name(String seed, String what) async {
    final mac = await _crypto.hmacSha256(
      key: await _keyFor(seed),
      message: what,
    );
    final hex = mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return hex.substring(0, _nameLength);
  }

  Future<Uint8List> _keyFor(String seed) async {
    final held = _key;
    if (held != null && _keySeed == seed) return held;
    final key = await _crypto.deriveMessageCacheKey(
      CryptoRepository.fromBase64(seed),
    );
    _keySeed = seed;
    _key = key;
    return key;
  }

  static Future<Directory> _defaultRoot() async => Directory(
    '${await StorageNamespace.profileDirectory(StorageNamespace.apply())}'
    '/message_cache',
  );
}
