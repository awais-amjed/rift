import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/custom_colors.dart';
import '../theme/theme_context.dart';

/// A destructive action that is one option among several, rather than the
/// commit at the foot of a form.
///
/// [AppButtonVariant.danger] is a solid wall of the error colour, which is
/// right for the single button that ends a confirmation and wrong the moment
/// there are two of them stacked: they out-shout the primary action and the
/// eye cannot tell which one it is about to press. This is the same height
/// and hairline ring as a secondary button, washed at 8% and lettered in the
/// error colour — loud enough to be found, quiet enough to sit in a list.
///
/// [isDangerous] is false for the *undo*, which is the inversion worth
/// spelling out: "Ban" does something to somebody and carries the colour,
/// "Lift ban" only gives it back and does not.
class QuietDangerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDangerous;
  final VoidCallback? onTap;

  const QuietDangerButton({
    super.key,
    required this.icon,
    required this.label,
    this.isDangerous = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final color = isDangerous ? CustomColors.error : themeState.textSecondary;

    return Material(
      color: isDangerous
          ? CustomColors.error.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: InkWell(
        borderRadius: BorderRadius.circular(K.radiusRow),
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Container(
          height: K.controlHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(
              color: isDangerous
                  ? CustomColors.error.withValues(alpha: 0.25)
                  : themeState.borderElevated,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.secondaryStrong.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
