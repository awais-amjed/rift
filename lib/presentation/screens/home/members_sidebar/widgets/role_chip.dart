import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';

/// A member's standing in the server: ADMIN, MOD.
///
/// Words rather than the icons this used to use — a shield and a wrench mean
/// nothing until someone tells you, and there is room on the row for the
/// three letters that don't need explaining.
class RoleChip extends StatelessWidget {
  final String label;
  final ThemeState themeState;

  /// Admins get the accent; lesser roles get a neutral fill, so seniority is
  /// visible without reading.
  final bool isPrimary;

  const RoleChip({
    super.key,
    required this.label,
    required this.themeState,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isPrimary
            ? themeState.primary.withValues(alpha: 0.14)
            : themeState.bgHover,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: AppText.roleChip.copyWith(
          color: isPrimary ? themeState.accentBright : themeState.textTertiary,
        ),
      ),
    );
  }
}
