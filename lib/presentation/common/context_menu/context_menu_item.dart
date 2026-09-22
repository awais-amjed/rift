import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';
import 'context_menu_sheet.dart';

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
    final themeState = context.theme;
    final color = isDangerous ? CustomColors.error : themeState.textSecondary;
    final radius = BorderRadius.circular(K.radiusRow);
    // A thumb's row in a sheet: past the 44px floor by padding, with the
    // label at row size rather than a pointer menu's quieter one.
    final inSheet = ContextMenuPresentation.isSheet(context);

    return Material(
      color: isDangerous
          ? CustomColors.error.withValues(alpha: 0.07)
          : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        hoverColor: isDangerous
            ? CustomColors.error.withValues(alpha: 0.14)
            : themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: inSheet ? 14 : 8,
          ),
          child: Row(
            spacing: inSheet ? 14 : 10,
            children: [
              Icon(icon, size: inSheet ? 19 : 15, color: color),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (inSheet ? AppText.row : AppText.rowQuiet).copyWith(
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
  }
}
