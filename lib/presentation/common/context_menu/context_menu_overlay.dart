import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Whatever had the keyboard before the menu took it — usually the composer
  /// — so closing the menu hands it straight back.
  FocusNode? _previousFocus;

  /// The menu's own, asked for outright when it opens. `autofocus` is not
  /// enough: it only takes focus when nothing else in the scope holds it, and
  /// a menu opened over a focused composer is exactly when something does.
  FocusNode? _focus;

  bool get isOpen => _entry != null;

  void show(BuildContext context, Widget menu, Offset globalPosition) {
    dismiss();

    // A phone gets the same menu as a sheet: there is no pointer to hang a
    // panel off, and a thumb needs rows the width of the screen.
    if (context.layoutMode.isCompact) {
      showContextMenuSheet(context, menu);
      return;
    }

    _previousFocus = FocusManager.instance.primaryFocus;
    final focus = _focus = FocusNode(debugLabel: 'context menu');
    _entry = OverlayEntry(
      // Focused, so Escape closes it the way it closes a dialog. The menu is
      // an overlay entry rather than a route, so nothing else would: the key
      // went to whatever was focused underneath and the menu stayed open.
      // A submenu closes with it — it is disposed along with this entry.
      builder: (_) => Focus(
        focusNode: focus,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            dismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
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
      ),
    );
    Overlay.of(context).insert(_entry!);
    focus.requestFocus();
    final watcher = ContextMenuWatcher.maybeOf(context);
    watcher?.onOpened();
    _onClosed = watcher?.onClosed;
  }

  void dismiss() {
    final wasOpen = _entry != null;
    _entry?.remove();
    _entry = null;
    final focus = _focus;
    _focus = null;
    // After the entry's last frame, which still holds the node.
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => focus.dispose());
    }
    final previous = _previousFocus;
    _previousFocus = null;
    if (wasOpen && previous != null && previous.context != null) {
      previous.requestFocus();
    }
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
