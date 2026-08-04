import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_shadows.dart';

/// The floating actions revealed at a message's top-right corner on hover.
class MessageHoverToolbar extends StatelessWidget {
  final ThemeState themeState;

  /// Both callbacks receive the tapped button's context so a popover (the
  /// reaction picker) can anchor to it.
  final void Function(BuildContext anchorContext)? onReact;
  final void Function(BuildContext anchorContext)? onCopy;

  const MessageHoverToolbar({
    super.key,
    required this.themeState,
    this.onReact,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: themeState.bgElevated,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: themeState.borderElevated),
        boxShadow: AppShadows.floatingBar,
      ),
      // Clipped so the buttons' hover fill stops at the rounded corners
      // instead of squaring them off, and given its own transparent Material
      // so that fill paints on the toolbar rather than behind it.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReact != null)
                _ToolbarButton(
                  icon: Icons.add_reaction_outlined,
                  tooltip: 'React',
                  themeState: themeState,
                  onTap: onReact!,
                ),
              if (onCopy != null)
                _ToolbarButton(
                  icon: Icons.content_copy_rounded,
                  tooltip: 'Copy text',
                  themeState: themeState,
                  onTap: onCopy!,
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
  final ThemeState themeState;
  final void Function(BuildContext anchorContext) onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onTap(context),
        hoverColor: themeState.bgHover,
        child: SizedBox(
          width: 30,
          height: 26,
          child: Icon(icon, size: 14, color: themeState.textSecondary),
        ),
      ),
    );
  }
}
