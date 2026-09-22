import 'package:flutter/material.dart';

import '../../responsive/shell_scope.dart';
import '../context_menu_region.dart';
import 'context_menu_layout.dart';
import 'context_menu_sheet.dart';
import 'context_menu_watcher.dart';

/// One open context menu, owned by whatever opened it.
///
/// Owned by the right-click region: placed against the pointer, dismissed by
/// a barrier, and shown as a bottom sheet on a phone. The owner calls
/// [dismiss] when it goes away, so a menu never outlives the row it belongs to.
class ContextMenuOverlay {
  OverlayEntry? _entry;

  /// Told when this menu closes, if something above its opener was watching.
  VoidCallback? _onClosed;

  bool get isOpen => _entry != null;

  void show(BuildContext context, Widget menu, Offset globalPosition) {
    dismiss();

    // A phone gets the same menu as a sheet: there is no pointer to hang a
    // panel off, and a thumb needs rows the width of the screen.
    if (context.layoutMode.isCompact) {
      showContextMenuSheet(context, menu);
      return;
    }

    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Full-screen barrier to dismiss on tap
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: dismiss,
              onSecondaryTap: dismiss,
            ),
          ),
          _PositionedMenu(
            position: globalPosition,
            child: ContextMenuScope(dismiss: dismiss, child: menu),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
    final watcher = ContextMenuWatcher.maybeOf(context);
    watcher?.onOpened();
    _onClosed = watcher?.onClosed;
  }

  void dismiss() {
    _entry?.remove();
    _entry = null;
    _onClosed?.call();
    _onClosed = null;
  }
}

class _PositionedMenu extends StatelessWidget {
  final Offset position;
  final Widget child;

  const _PositionedMenu({required this.position, required this.child});

  @override
  Widget build(BuildContext context) {
    // Fills the overlay and places the menu inside it. The layout box itself
    // never answers a hit test, so a tap that misses the menu still reaches the
    // dismiss barrier underneath.
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: ContextMenuLayout.atPoint(position),
        child: child,
      ),
    );
  }
}
