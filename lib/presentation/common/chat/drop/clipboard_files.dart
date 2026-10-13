import 'dart:io' show File, FileSystemEntity;
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/host_platform.dart';
import 'chat_drop_relay.dart';

/// What Ctrl+V in the composer should attach rather than type: files copied
/// in a file manager, or a picture — a screenshot, an image copied from a
/// browser. Flutter's clipboard reads text only, so without this a copied
/// picture pasted nothing at all.
abstract final class ClipboardFiles {
  /// The files to attach, or null when the paste is text and the field
  /// should take it as usual.
  ///
  /// Copied files win over text, because a file manager offers their paths
  /// as text too and nobody pasting a file wants its path. Text wins over a
  /// picture: an office app copies a selection as both, and the words are
  /// what was meant. Desktop only — on the web the browser handles the key
  /// itself, and on a phone a keyboard inserts pictures its own way.
  static Future<List<DroppedFile>?> read() async {
    if (!HostPlatform.isDesktop) return null;
    try {
      final files = await _copiedFiles();
      if (files.isNotEmpty) return files;
      if (await Clipboard.hasStrings()) return null;
      final picture = await Pasteboard.image;
      if (picture == null || picture.isEmpty) return null;
      final png = await _asPng(picture);
      return [
        (
          name: 'image.png',
          file: XFile.fromData(png, mimeType: 'image/png', length: png.length),
          size: png.length,
          mimeType: 'image/png',
          temporary: false,
        ),
      ];
    } catch (e) {
      HelperMethods.printDebug('[Paste] reading the clipboard failed: $e');
      return null;
    }
  }

  /// Copied files that are files: a folder has no bytes to send, and is left
  /// out the way a dropped one is.
  static Future<List<DroppedFile>> _copiedFiles() async {
    final files = <DroppedFile>[];
    for (final path in await Pasteboard.files()) {
      if (path.isEmpty || !FileSystemEntity.isFileSync(path)) continue;
      files.add((
        name: p.basename(path),
        file: XFile(path),
        size: await File(path).length(),
        mimeType: null,
        temporary: false,
      ));
    }
    return files;
  }

  /// The picture as a PNG. Windows hands the clipboard's bitmap over as an
  /// uncompressed BMP — a screenshot of one screen is 8 MB of it — so
  /// anything that is not already a PNG is re-encoded.
  static Future<Uint8List> _asPng(Uint8List bytes) async {
    const signature = [0x89, 0x50, 0x4E, 0x47];
    final isPng =
        bytes.length > signature.length &&
        Iterable.generate(
          signature.length,
        ).every((i) => bytes[i] == signature[i]);
    if (isPng) return bytes;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) throw StateError('the picture could not be encoded');
    return data.buffer.asUint8List();
  }
}
