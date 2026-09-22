import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';
import '../context_menu_region.dart';
import 'context_menu_item.dart';
import 'context_menu_layout.dart';
import 'context_menu_sheet.dart';

/// A context-menu row that opens a second panel beside it, Windows-style.
///
/// Opens on hover and stays open while the pointer is over either the row or
/// the panel, with a short grace period so moving diagonally across the gap
/// doesn't close it. Clicking works too, for touch and long-press.
///
/// The panel is its own [OverlayEntry] inserted above the menu's, so it takes
/// clicks before the dismiss barrier does. It only hit-tests where the panel
/// actually is — the rest of the screen still reaches the menu underneath, so
/// you can slide straight onto another row.
class ContextMenuSubmenuItem extends StatefulWidget {
  final IconData icon;
  final String label;

  /// Built when the submenu opens, inside a [ContextMenuScope] whose dismiss
  /// closes the whole stack — so an action in there can shut the lot, while a
  /// toggle can leave it open the way the top-level toggles do.
  final WidgetBuilder submenuBuilder;

  const ContextMenuSubmenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.submenuBuilder,
  });

  @override
  State<ContextMenuSubmenuItem> createState() => _ContextMenuSubmenuItemState();
}

class _ContextMenuSubmenuItemState extends State<ContextMenuSubmenuItem> {
  /// Long enough to cross the gap between the row and the panel, short enough
  /// that a panel you've left doesn't linger.
  static const _closeGrace = Duration(milliseconds: 180);

  /// Horizontal gap from the parent panel, on whichever side it opens, and the
  /// lift that lines the submenu's first row up with this one —
  /// `ContextMenuPanel` pads by 6.
  static const _gap = 4.0;
  static const _panelPadding = 6.0;

  final GlobalKey _rowKey = GlobalKey();
  OverlayEntry? _entry;
  Timer? _closeTimer;

  bool get _isOpen => _entry != null;

  void _open() {
    _closeTimer?.cancel();
    if (_isOpen) return;

    final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.of(context);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;

    // The whole row, in overlay coordinates, grown by the gap and by the
    // panel's own padding. Both edges matter: the submenu opens past the right
    // one, and when there isn't room it opens before the *left* one — clear of
    // the parent panel rather than across it.
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchor = Rect.fromLTRB(
      topLeft.dx - _gap,
      topLeft.dy - _panelPadding,
      topLeft.dx + box.size.width + _gap,
      topLeft.dy + box.size.height + _panelPadding,
    );

    final dismissAll = ContextMenuScope.of(context);

    _entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: ContextMenuLayout(anchor: anchor),
          child: MouseRegion(
            onEnter: (_) => _closeTimer?.cancel(),
            onExit: (_) => _scheduleClose(),
            child: ContextMenuScope(
              dismiss: () {
                _close();
                dismissAll?.call();
              },
              child: Builder(builder: widget.submenuBuilder),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(_entry!);
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(_closeGrace, _close);
  }

  void _close() {
    _closeTimer?.cancel();
    _closeTimer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    // The parent menu going away takes this with it.
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = ContextMenuPresentation.of(context);
    final themeState = context.theme;
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 16,
      color: themeState.textQuaternary,
    );
    // No room beside a sheet, so the submenu takes the sheet's place and
    // its heading carries the way back.
    if (sheet != null) {
      return ContextMenuItem(
        icon: widget.icon,
        label: widget.label,
        onTap: () => sheet.pushSubmenu(widget.submenuBuilder),
        trailing: chevron,
      );
    }
    return MouseRegion(
      onEnter: (_) => _open(),
      onExit: (_) => _scheduleClose(),
      child: KeyedSubtree(
        key: _rowKey,
        child: ContextMenuItem(
          icon: widget.icon,
          label: widget.label,
          onTap: () => _isOpen ? _close() : _open(),
          trailing: chevron,
        ),
      ),
    );
  }
}
