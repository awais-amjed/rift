import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// One round control in the call's floating bar.
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

  const ControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.isDimmed = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        Color bgColor = Colors.transparent;
        Color iconColor;

        if (isActive) {
          bgColor = themeState.channelActiveBg;
          iconColor = themeState.primary;
        } else if (isError) {
          bgColor = CustomColors.error.withValues(alpha: 0.1);
          iconColor = CustomColors.error;
        } else if (isDimmed) {
          bgColor = themeState.bgTertiary;
          iconColor = themeState.textTertiary;
        } else {
          iconColor = themeState.textSecondary;
        }

        return Tooltip(
          message: tooltip,
          child: Material(
            color: bgColor,
            borderRadius: BorderRadius.circular(K.radiusRow),
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(K.radiusRow),
              hoverColor: themeState.bgHover,
              onTap: onTap,
              child: SizedBox(
                width: 46,
                height: 46,
                child: Icon(icon, size: 21, color: iconColor),
              ),
            ),
          ),
        );
      },
    );
  }
}
