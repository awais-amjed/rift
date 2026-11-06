import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
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
  ///
  /// On a phone the call's controls share a row with its name instead, over
  /// mute, deafen and settings, so there it is drawn as those are
  /// (`DockIconButton`): a bare square a thumb's size, lined up beneath.
  final bool dense;

  /// A word beside the icon, for a [dense] tile with room to say what it
  /// does: a row of one or two is wide enough, and a lone icon on a wide tile
  /// reads as decoration.
  final String? label;

  const ControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.isDimmed = false,
    this.isError = false,
    this.dense = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final flat = dense && context.layoutMode.isCompact;
    Color bgColor = dense && !flat ? themeState.bgHover : Colors.transparent;
    Color iconColor;

    if (isActive) {
      bgColor = themeState.channelActiveBg;
      iconColor = themeState.primary;
    } else if (isError) {
      bgColor = CustomColors.error.withValues(alpha: flat ? 0.12 : 0.1);
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
            // The shared control height, square: they were 46, beside a
            // Leave that came out 44 and every other button in the app.
            width: flat
                ? K.touchTargetMin
                : dense
                ? double.infinity
                : K.controlHeight,
            height: dense && !flat ? K.dockCallButtonHeight : K.controlHeight,
            child: switch (label) {
              final label? => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  Icon(icon, size: K.iconButton, color: iconColor),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(color: iconColor),
                    ),
                  ),
                ],
              ),
              null => Icon(
                icon,
                size: dense ? K.iconButton : K.iconLarge,
                color: iconColor,
              ),
            },
          ),
        ),
      ),
    );
  }
}
