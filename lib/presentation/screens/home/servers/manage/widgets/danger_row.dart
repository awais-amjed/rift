import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// One irreversible action on the danger page: what it is, what it does, and
/// the one button that does it.
class DangerRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Widget action;

  const DangerRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: CustomColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Icon(icon, size: 18, color: CustomColors.error),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.row.copyWith(color: themeState.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: AppText.secondary.copyWith(
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}
