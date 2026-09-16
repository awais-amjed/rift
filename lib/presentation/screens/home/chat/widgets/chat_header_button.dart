import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../responsive/shell_scope.dart';

/// A square control in a panel header.
///
/// [isPrimary] promotes the button to an accent tile — for the one header
/// control that *starts* something rather than toggling a view.
///
/// There is no "active" state any more: it existed for the members toggle,
/// which is gone from the header, and every remaining control here acts rather
/// than latches.
class ChatHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isPrimary;
  final VoidCallback onTap;

  const ChatHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final radius = BorderRadius.circular(K.radiusRow);
        // A thumb's target on a phone; a pointer's on a desktop, where the
        // header is a strip of chrome rather than the top of the screen.
        final size = context.layoutMode.isCompact
            ? K.touchTargetMin
            : (isPrimary ? 30.0 : 32.0);

        final fill = isPrimary
            ? themeState.primary.withValues(alpha: 0.12)
            : Colors.transparent;
        final iconColor = isPrimary
            ? themeState.accentBright
            : themeState.textTertiary;

        return Tooltip(
          message: tooltip,
          waitDuration: K.tooltipDelay,
          child: Material(
            color: fill,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              hoverColor: themeState.bgActive,
              onTap: onTap,
              child: Container(
                width: size,
                height: size,
                decoration: isPrimary
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: themeState.primary.withValues(alpha: 0.3),
                        ),
                      )
                    : null,
                child: Icon(icon, size: 17, color: iconColor),
              ),
            ),
          ),
        );
      },
    );
  }
}
