import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// One moderation control in the members dialog.
///
/// Reads inverted on purpose: the *dangerous* state is the one that isn't set
/// yet. "Server Mute" carries the red wash because pressing it does something
/// to someone; "Unmute" is plain, because undoing it doesn't.
class ModerationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final ThemeState themeState;
  final VoidCallback? onTap;

  const ModerationButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.themeState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? themeState.textSecondary : CustomColors.error;

    return Material(
      color: isActive
          ? Colors.transparent
          : CustomColors.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.secondary.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
