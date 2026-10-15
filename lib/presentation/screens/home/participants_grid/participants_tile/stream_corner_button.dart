import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';

/// One glass button in the corner of a watched stream. The same glass as the
/// badges in the opposite corner, so the two read as one set.
class StreamCornerButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const StreamCornerButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.bgSecondary.withValues(alpha: 0.85),
              borderRadius: radius,
              border: Border.all(color: theme.borderElevated),
            ),
            // Inside the fill, or the hover is painted under it.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                borderRadius: radius,
                hoverColor: theme.bgHover,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    icon,
                    size: K.iconButton,
                    color: theme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
