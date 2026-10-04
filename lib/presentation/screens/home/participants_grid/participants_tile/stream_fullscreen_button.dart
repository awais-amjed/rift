import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';

/// Full screen, or back out of it, in the corner of a watched stream. The same
/// glass as the badges in the opposite corner, so the two read as one set.
class StreamFullscreenButton extends StatelessWidget {
  final bool isFullscreen;
  final VoidCallback onTap;

  const StreamFullscreenButton({
    super.key,
    required this.isFullscreen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    return Tooltip(
      message: isFullscreen ? 'Exit full screen' : 'Full screen',
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
                    isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
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
