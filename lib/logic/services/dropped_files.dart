import 'dart:io' show FileSystemEntity, Platform;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';

import 'attachment_staging.dart';
import 'file_save/save_target.dart';

/// A file handed to the composer — by the picker, or dropped on a chat pane —
/// not read yet: the composer decides whether it is small enough to hold.
///
/// The name travels beside the file rather than in it: off the web,
/// `XFile.fromData` ignores the name it is given, so a file wrapped from
/// bytes would arrive called "".
///
/// `temporary` marks a copy made to be sent rather than the person's own file
/// (`PendingAttachment.temporary`), which is deleted once it has gone.
typedef DroppedFile = ({
  String name,
  XFile file,
  int size,
  String? mimeType,
  bool temporary,
});

/// What a file dragged onto a chat pane is, asked of the disk rather than in
/// the pane that caught it.
abstract final class DroppedFiles {
  /// Asked of the disk as well as the plugin: only its macOS side reports a
  /// folder as one, and on Linux and Windows a folder arrives as a file that
  /// then fails to read.
  static bool isFolder(DropItem item) =>
      item is DropItemDirectory ||
      (!kIsWeb &&
          item.path.isNotEmpty &&
          FileSystemEntity.isDirectorySync(item.path));

  /// The file as the composer will read it.
  ///
  /// The macOS build is sandboxed, and a file dragged in from Finder is
  /// readable only inside the security-scoped access its bookmark grants. So
  /// there it is read here, under that access, rather than later by the
  /// composer: held in memory if it is small, copied to a scratch file a
  /// piece at a time if it is not. Everywhere else the dropped file is a path
  /// that stays readable, and is passed on unread.
  static Future<DroppedFile> read(DropItem file) async {
    final size = await file.length();
    final bookmark = file.extraAppleBookmark;
    final scoped =
        !kIsWeb &&
        Platform.isMacOS &&
        bookmark != null &&
        await DesktopDrop.instance.startAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
    if (!scoped) {
      return (
        name: file.name,
        file: file,
        size: size,
        mimeType: file.mimeType,
        temporary: false,
      );
    }
    try {
      final XFile readable;
      final copied = size > AttachmentStaging.inMemoryMaxBytes;
      if (!copied) {
        readable = XFile.fromData(await file.readAsBytes(), length: size);
      } else {
        final scratch = await scratchTarget(file.name);
        await for (final piece in file.openRead()) {
          await scratch.add(Uint8List.fromList(piece));
        }
        await scratch.close();
        readable = scratch.file;
      }
      return (
        name: file.name,
        file: readable,
        size: size,
        mimeType: file.mimeType,
        temporary: copied,
      );
    } finally {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    }
  }
}
