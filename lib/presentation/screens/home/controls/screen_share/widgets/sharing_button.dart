import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/theme_context.dart';

/// The screen share control while a share runs: stop on the left, and a
/// narrow chevron on the right that opens the stream's menu. One lit
/// control in two halves, the way the bar's other toggles light up when on.
class SharingButton extends StatelessWidget {
  final VoidCallback onStop;
  final VoidCallback onMenu;

  /// The user dock's shape: see [ControlButton.dense]. Stop takes whatever
  /// width the chevron leaves.
  final bool dense;

  /// The bar's controls are 46 square; the chevron is half of one.
  static const double _height = 46;
  static const double _chevronWidth = 24;

  const SharingButton({
    super.key,
    required this.onStop,
    required this.onMenu,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    const radius = Radius.circular(K.radiusRow);
    final height = dense ? K.dockCallButtonHeight : _height;
    final stop = Tooltip(
      message: 'Stop sharing',
      waitDuration: dense ? K.tooltipDelay : null,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: const BorderRadius.horizontal(left: radius),
        hoverColor: themeState.bgHover,
        onTap: onStop,
        child: SizedBox(
          width: dense ? double.infinity : _height,
          height: height,
          child: Icon(
            Icons.stop_screen_share_outlined,
            size: dense ? K.iconButton : K.iconLarge,
            color: themeState.primary,
          ),
        ),
      ),
    );
    return Material(
      color: themeState.channelActiveBg,
      borderRadius: const BorderRadius.all(radius),
      child: Row(
        mainAxisSize: dense ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (dense) Expanded(child: stop) else stop,
          Tooltip(
            message: 'Stream options',
            waitDuration: dense ? K.tooltipDelay : null,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: const BorderRadius.horizontal(right: radius),
              hoverColor: themeState.bgHover,
              onTap: onMenu,
              child: SizedBox(
                width: _chevronWidth,
                height: height,
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: K.iconButton,
                  color: themeState.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
