import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/theme_context.dart';

/// The screen share control while a share runs: stop on the left, and a
/// narrow chevron on the right that opens the stream's menu. One lit
/// control in two halves, the way the bar's other toggles light up when on.
class SharingButton extends StatelessWidget {
  final VoidCallback onStop;
  final VoidCallback onMenu;

  /// The bar's controls are 46 square; the chevron is half of one.
  static const double _height = 46;
  static const double _chevronWidth = 24;

  const SharingButton({super.key, required this.onStop, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    const radius = Radius.circular(K.radiusRow);
    return Material(
      color: themeState.channelActiveBg,
      borderRadius: const BorderRadius.all(radius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Stop sharing',
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: const BorderRadius.horizontal(left: radius),
              hoverColor: themeState.bgHover,
              onTap: onStop,
              child: SizedBox.square(
                dimension: _height,
                child: Icon(
                  Icons.stop_screen_share_outlined,
                  size: K.iconLarge,
                  color: themeState.primary,
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Stream options',
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: const BorderRadius.horizontal(right: radius),
              hoverColor: themeState.bgHover,
              onTap: onMenu,
              child: SizedBox(
                width: _chevronWidth,
                height: _height,
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
