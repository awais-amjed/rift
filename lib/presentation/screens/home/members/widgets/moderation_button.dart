import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';

/// One moderation control in the members dialog.
///
/// Reads inverted on purpose: the *dangerous* state is the one that isn't set
/// yet. "Server Mute" carries the red wash because pressing it does something
/// to someone; "Unmute" is plain, because undoing it doesn't.
class ModerationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const ModerationButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final color = isActive ? themeState.textSecondary : CustomColors.error;

    // Same height and hairline ring as a secondary AppButton, so the panel
    // reads as a row of the app's buttons rather than three of its own.
    return Material(
      color: isActive
          ? Colors.transparent
          : CustomColors.error.withValues(alpha: 0.08),
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
              color: isActive
                  ? themeState.borderElevated
                  : CustomColors.error.withValues(alpha: 0.25),
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
