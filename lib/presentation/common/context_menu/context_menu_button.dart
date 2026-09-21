import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../theme/theme_context.dart';
import '../context_menu_region.dart';

/// The ••• on a row that opens the menu its right-click opens.
///
/// Right-click is a power-user gesture that plenty of people never try on an
/// app's own content, and every setting behind it is, for them, a setting that
/// doesn't exist. This makes the same menu findable without taking the
/// right-click away.
///
/// [visible] is the row's hover or selection. Hidden, the button still takes
/// its 26px — transparent rather than removed — so the label beside it doesn't
/// reflow the moment the pointer arrives. It stays focusable either way, so
/// the menu can be reached from the keyboard.
class ContextMenuButton extends StatefulWidget {
  final Widget menu;
  final bool visible;
  final String tooltip;

  const ContextMenuButton({
    super.key,
    required this.menu,
    required this.visible,
    this.tooltip = 'More options',
  });

  static const double size = 26;

  @override
  State<ContextMenuButton> createState() => _ContextMenuButtonState();
}

class _ContextMenuButtonState extends State<ContextMenuButton> {
  final ContextMenuOverlay _overlay = ContextMenuOverlay();
  bool _focused = false;

  @override
  void dispose() {
    _overlay.dismiss();
    super.dispose();
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    // Opens from the button's lower-left, so the menu hangs off it the way a
    // right-click menu hangs off the pointer.
    final anchor = box.localToGlobal(Offset(0, box.size.height + 4));
    _overlay.show(context, widget.menu, anchor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final shown = widget.visible || _focused || _overlay.isOpen;
    final radius = BorderRadius.circular(K.radiusRow);

    return Opacity(
      opacity: shown ? 1 : 0,
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: K.tooltipDelay,
        child: Material(
          color: shown ? theme.bgHover : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: radius,
            hoverColor: theme.bgActive,
            onFocusChange: (focused) => setState(() => _focused = focused),
            onTap: _open,
            child: SizedBox.square(
              dimension: ContextMenuButton.size,
              child: Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: theme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
