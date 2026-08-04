import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';

/// One row in a context menu.
///
/// Destructive items carry a standing red wash rather than only red text —
/// in a list of otherwise identical rows, colour alone on a 14px label is too
/// easy to miss on the way to clicking it.
class ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDangerous;
  final VoidCallback onTap;

  /// Trailing widget — an unread count on "Mark as read", a shortcut hint.
  final Widget? trailing;

  const ContextMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDangerous = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final color = isDangerous
            ? CustomColors.error
            : themeState.textSecondary;
        final radius = BorderRadius.circular(9);

        return Material(
          color: isDangerous
              ? CustomColors.error.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            hoverColor: isDangerous
                ? CustomColors.error.withValues(alpha: 0.14)
                : themeState.bgHover,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                spacing: 10,
                children: [
                  Icon(icon, size: 15, color: color),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowQuiet.copyWith(
                        fontSize: 13,
                        color: color,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
