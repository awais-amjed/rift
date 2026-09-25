import 'package:flutter/material.dart';

import '../../../../data/classes/panel_block.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../context_menu/context_menu_item.dart';
import '../../context_menu/context_menu_overlay.dart';
import '../../context_menu/context_menu_panel.dart';

/// A bot's `select` block: a chip that opens a menu of its options.
///
/// The menu is Rift's own [ContextMenuPanel], opened under the chip, so it
/// looks like every other menu in the app. It used to be Material's
/// `PopupMenuButton`, the one menu with its own radius, shadow and rows. The
/// bot names the action once; each option carries the value that comes back
/// with it.
class PanelSelect extends StatefulWidget {
  final PanelBlock block;
  final void Function(String action, String? value)? onAction;

  const PanelSelect({super.key, required this.block, this.onAction});

  @override
  State<PanelSelect> createState() => _PanelSelectState();
}

class _PanelSelectState extends State<PanelSelect> {
  final ContextMenuOverlay _menu = ContextMenuOverlay();

  @override
  void dispose() {
    _menu.dismiss();
    super.dispose();
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    // Under the chip, left edges together, as a dropdown opens.
    final below = box.localToGlobal(Offset(0, box.size.height + 4));
    final onAction = widget.onAction!;
    final block = widget.block;
    _menu.show(
      context,
      ContextMenuPanel(
        children: [
          for (final option in block.actions)
            ContextMenuItem(
              label: option.label,
              onTap: () {
                _menu.dismiss();
                onAction(block.action!, option.value ?? option.label);
              },
            ),
        ],
      ),
      below,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final enabled = widget.onAction != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: themeState.bgHover,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusRow),
          onTap: enabled ? _open : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(K.radiusRow),
              border: Border.all(color: themeState.borderPrimary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Text(
                  widget.block.text ?? 'Choose…',
                  style: AppText.secondary.copyWith(
                    color: themeState.textSecondary,
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  size: 15,
                  color: themeState.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
