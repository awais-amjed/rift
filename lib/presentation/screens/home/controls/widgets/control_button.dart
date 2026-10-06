import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// One round control in the call's floating bar, or — [dense] — in the
/// user dock's call row.
///
/// Its own file because the bar is no longer the only thing that puts a
/// control in it — the soundboard's button opens a popover and so has to be a
/// stateful widget of its own, and a second copy of this styling is two
/// things that can drift apart in a row of five.
class ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isDimmed;
  final bool isError;
  final String tooltip;
  final VoidCallback onTap;

  /// The dock's shape: a filled tile [K.dockCallButtonHeight] tall that takes
  /// the width its slot gives it. Filled because the dock is a surface of
  /// its own, where a bare glyph in a row of four reads as a label.
  final bool dense;

  const ControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.isDimmed = false,
    this.isError = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    Color bgColor = dense ? themeState.bgHover : Colors.transparent;
    Color iconColor;

    if (isActive) {
      bgColor = themeState.channelActiveBg;
      iconColor = themeState.primary;
    } else if (isError) {
      bgColor = CustomColors.error.withValues(alpha: 0.1);
      iconColor = CustomColors.error;
    } else if (isDimmed) {
      if (!dense) bgColor = themeState.bgTertiary;
      iconColor = themeState.textTertiary;
    } else {
      iconColor = themeState.textSecondary;
    }

    return Tooltip(
      message: tooltip,
      waitDuration: dense ? K.tooltipDelay : null,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusRow),
          hoverColor: dense ? themeState.bgActive : themeState.bgHover,
          onTap: onTap,
          child: SizedBox(
            width: dense ? double.infinity : 46,
            height: dense ? K.dockCallButtonHeight : 46,
            child: Icon(
              icon,
              size: dense ? K.iconButton : K.iconLarge,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
