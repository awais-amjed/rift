import 'package:flutter/material.dart';

import '../../../theme/app_shadows.dart';
import '../../../theme/custom_colors.dart';
import '../../../../data/constants.dart';
import '../../../theme/theme_context.dart';

/// The floating actions revealed at a message's top-right corner on hover.
///
/// Every action a message has is here, not only the safe ones: edit and
/// delete used to be reachable by right-click alone, which is a gesture
/// nobody discovers on a chat row. Delete is the odd one out and looks it —
/// red glyph, red hover — so a row of near-identical icons can't lead you
/// into it by accident.
class MessageHoverToolbar extends StatelessWidget {
  /// Each callback receives the tapped button's context so a popover (the
  /// reaction picker) can anchor to it. Null hides that action.
  final void Function(BuildContext anchorContext)? onReact;
  final void Function(BuildContext anchorContext)? onCopy;
  final void Function(BuildContext anchorContext)? onEdit;
  final void Function(BuildContext anchorContext)? onDelete;

  const MessageHoverToolbar({
    super.key,
    this.onReact,
    this.onCopy,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      decoration: BoxDecoration(
        color: themeState.bgElevated,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: themeState.borderElevated),
        boxShadow: AppShadows.floatingBar,
      ),
      // Clipped so the buttons' hover fill stops at the rounded corners
      // instead of squaring them off, and given its own transparent Material
      // so that fill paints on the toolbar rather than behind it.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: Material(
          color: Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReact != null)
                _ToolbarButton(
                  icon: Icons.add_reaction_outlined,
                  tooltip: 'React',

                  onTap: onReact!,
                ),
              if (onCopy != null)
                _ToolbarButton(
                  icon: Icons.content_copy_outlined,
                  tooltip: 'Copy text',

                  onTap: onCopy!,
                ),
              if (onEdit != null)
                _ToolbarButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit',

                  onTap: onEdit!,
                ),
              if (onDelete != null)
                _ToolbarButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',

                  isDangerous: true,
                  onTap: onDelete!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isDangerous;
  final void Function(BuildContext anchorContext) onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isDangerous = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onTap(context),
        hoverColor: isDangerous
            ? CustomColors.error.withValues(alpha: 0.14)
            : themeState.bgHover,
        child: SizedBox(
          width: 32,
          height: 28,
          child: Icon(
            icon,
            size: 15,
            color: isDangerous ? CustomColors.error : themeState.textSecondary,
          ),
        ),
      ),
    );
  }
}
