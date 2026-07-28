import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';

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
    return Material(
      color: themeState.bgElevated,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: themeState.borderPrimary),
        ),
        padding: const EdgeInsets.all(2),
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
        borderRadius: BorderRadius.circular(7),
        hoverColor: themeState.bgHover,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: themeState.textTertiary),
        ),
      ),
    );
  }
}
