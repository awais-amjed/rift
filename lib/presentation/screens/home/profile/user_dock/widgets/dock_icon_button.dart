import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';

/// One of the small square controls on the right of the user dock.
///
/// [isError] is for states you are *in* rather than actions — muted, deafened.
/// They keep a standing tint instead of only colouring the glyph, so the state
/// is visible at a glance in a row of otherwise identical buttons.
class DockIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isError;
  final VoidCallback onTap;

  const DockIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final radius = BorderRadius.circular(K.radiusRow);

        return Tooltip(
          message: tooltip,
          waitDuration: K.tooltipDelay,
          child: Material(
            color: isError
                ? CustomColors.error.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: radius,
              hoverColor: themeState.bgActive,
              onTap: onTap,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Icon(
                  icon,
                  size: 15,
                  color: isError
                      ? CustomColors.error
                      : themeState.textSecondary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
