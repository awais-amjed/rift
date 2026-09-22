import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logic/services/host_platform.dart';
import 'context_menu/context_menu_overlay.dart';

/// Lets menu content close the menu it lives in.
///
/// The menu is an [OverlayEntry], not a route, so `Navigator.pop` can't reach
/// it. Actions that navigate away — opening a DM — must dismiss; toggles like
/// mute deliberately leave it open so you can flip several.
class ContextMenuScope extends InheritedWidget {
  final VoidCallback dismiss;

  const ContextMenuScope({
    super.key,
    required this.dismiss,
    required super.child,
  });

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContextMenuScope>()?.dismiss;

  @override
  bool updateShouldNotify(ContextMenuScope oldWidget) => false;
}

/// Opens [contextMenu] on a right-click, or on a long press on touch, at the
/// point that was pressed. Content inside can close it through
/// [ContextMenuScope].
class ContextMenuRegion extends StatefulWidget {
  final Widget child;
  final Widget contextMenu;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.contextMenu,
  });

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  final ContextMenuOverlay _overlay = ContextMenuOverlay();

  @override
  void dispose() {
    _overlay.dismiss();
    super.dispose();
  }

  /// A long press is the touch equivalent of a right-click, and the only
  /// signal that it has registered is the buzz — the menu opens *after* the
  /// press is held, so without it the finger spends half a second on a screen
  /// that appears to be ignoring it. Mobile only: a desktop has no vibrator,
  /// and long-press there is a fallback for a right-click that already worked.
  void _openByTouch(Offset position) {
    if (HostPlatform.isMobile) HapticFeedback.mediumImpact();
    _overlay.show(context, widget.contextMenu, position);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _overlay.show(context, widget.contextMenu, details.globalPosition),
      onLongPressStart: (details) => _openByTouch(details.globalPosition),
      child: widget.child,
    );
  }
}
