import 'dart:async';
import 'dart:io' show FileSystemEntity, Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../logic/helper_methods.dart';
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

  /// The file's bytes, read while the sandbox allows it.
  ///
  /// The macOS build is sandboxed, and a file dragged in from Finder is
  /// readable only inside the security-scoped access its bookmark grants. So
  /// it is read here, under that access, rather than later by the composer.
  Future<DroppedFile> _read(DropItem file) async {
    final bookmark = file.extraAppleBookmark;
    final scoped =
        !kIsWeb &&
        Platform.isMacOS &&
        bookmark != null &&
        await DesktopDrop.instance.startAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
    try {
      return (
        name: file.name,
        bytes: await file.readAsBytes(),
        mimeType: file.mimeType,
      );
    } finally {
      if (scoped) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
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
