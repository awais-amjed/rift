import 'dart:async';
import 'dart:io' show FileSystemEntity, Platform;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/attachment_staging.dart';
import '../../../../logic/services/file_save/save_target.dart';
import 'chat_drop_overlay.dart';
import 'chat_drop_relay.dart';

/// A chat pane that takes files dragged in from the desktop.
///
/// Wraps the whole conversation, header to composer, and hands what lands to
/// the composer through a [ChatDropRelay]. While files hover it says so over
/// the pane; it says nothing when the composer could not take them.
class ChatDropZone extends StatefulWidget {
  final Widget child;

  const ChatDropZone({super.key, required this.child});

  @override
  State<ChatDropZone> createState() => _ChatDropZoneState();
}

class _ChatDropZoneState extends State<ChatDropZone> {
  final ChatDropRelay _relay = ChatDropRelay();
  bool _hovering = false;

  /// The plugin reports every drag over the window to every target, including
  /// one under a dialog or a page pushed on top — so a drop is ours only while
  /// this pane's route is the one in front.
  bool get _inFront => ModalRoute.isCurrentOf(context) ?? true;

  void _setHovering(bool value) {
    if (_hovering != value && mounted) setState(() => _hovering = value);
  }

  Future<void> _onDone(DropDoneDetails details) async {
    _setHovering(false);
    if (!_inFront || !_relay.accepts) return;
    // A folder has no bytes to send; the files beside it still go.
    final files = details.files.where((f) => !_isFolder(f)).toList();
    if (files.length < details.files.length) {
      HelperMethods.showError(error: "Folders can't be attached.");
    }
    try {
      _relay.deliver([for (final file in files) await _read(file)]);
    } catch (e) {
      HelperMethods.printDebug('[ChatDrop] reading a dropped file failed: $e');
      HelperMethods.showError(error: "Couldn't attach that file.");
    }
  }

  /// Asked of the disk as well as the plugin: only its macOS side reports a
  /// folder as one, and on Linux and Windows a folder arrives as a file that
  /// then fails to read.
  bool _isFolder(DropItem item) =>
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
  Future<DroppedFile> _read(DropItem file) async {
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

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => _setHovering(_inFront && _relay.accepts),
      onDragExited: (_) => _setHovering(false),
      onDragDone: (details) => unawaited(_onDone(details)),
      child: ChatDropScope(
        relay: _relay,
        child: Stack(
          // The pane keeps the constraints it was given; the overlay only
          // covers it.
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(child: ChatDropOverlay(visible: _hovering)),
          ],
        ),
      ),
    );
  }
}
