import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../helper_methods.dart';

/// Where a decrypted chat sound is played from.
///
/// Attachments are decrypted message content and never go to disk. Android,
/// Windows and the web play the bytes from memory, but `audioplayers` on
/// Linux cannot: given bytes it wrote them to the shared temporary folder,
/// readable by every account on the machine, and never deleted them. So on
/// Linux the bytes go in a folder of this process's own under
/// `$XDG_RUNTIME_DIR` — memory-backed (tmpfs), the user's alone — and are
/// deleted when the player lets go of them, and any a crashed run left behind
/// are deleted the next time one is written.
class ChatAudioSource {
  final Source source;
  final File? _file;

  ChatAudioSource._(this.source, this._file);

  static Future<ChatAudioSource> of(Uint8List bytes, String mime) async {
    if (kIsWeb || !Platform.isLinux) {
      return ChatAudioSource._(BytesSource(bytes, mimeType: mime), null);
    }
    final dir = await _folder();
    final name = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return ChatAudioSource._(
      DeviceFileSource(file.path, mimeType: mime),
      file,
    );
  }

  /// Deletes the copy, if there is one. Call once the player has stopped
  /// with it.
  Future<void> release() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.delete();
    } on FileSystemException catch (e) {
      HelperMethods.printDebug('Chat audio: copy not deleted: ${e.message}');
    }
  }

  static final Random _random = Random.secure();
  static Future<Directory>? _made;

  static Future<Directory> _folder() => _made ??= _make();

  static Future<Directory> _make() async {
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    // Without a runtime folder (no login session), the temporary folder is
    // the only place left; the folder below is still the user's alone.
    final base = runtime != null && runtime.isNotEmpty
        ? runtime
        : Directory.systemTemp.path;
    final root = Directory('$base/rift-chat-audio');
    final own = Directory('${root.path}/$pid');
    await own.create(recursive: true);
    await Process.run('chmod', ['700', root.path, own.path]);
    await _sweep(root);
    return own;
  }

  /// Deletes what runs no longer alive left behind. Several profiles can run
  /// at once, each in its own folder, so only a dead process's goes.
  static Future<void> _sweep(Directory root) async {
    try {
      await for (final entry in root.list()) {
        final owner = int.tryParse(entry.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
        ));
        if (owner == null || owner == pid) continue;
        if (await Directory('/proc/$owner').exists()) continue;
        await entry.delete(recursive: true);
      }
    } on FileSystemException catch (e) {
      HelperMethods.printDebug('Chat audio: sweep failed: ${e.message}');
    }
  }
}
