import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';
import 'manage_panel.dart';

/// One irreversible action on the danger page: what it is, what it does, and
/// the one button that does it.
///
/// Under a [ManageReadOnly] the button is not drawn. The page is still worth
/// reading there — it says what the danger zone is for and how to hand the
/// server on instead — but a solid red "Delete server" sitting under a notice
/// explaining that nothing here can be changed reads as a live control, and
/// the surrounding [AbsorbPointer] means pressing it does nothing at all. A
/// control that looks live and is not is worse than one that is missing,
/// and on this particular button it is a great deal worse.
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
    final readOnly = ManageReadOnly.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: CustomColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Icon(icon, size: K.iconButton, color: CustomColors.error),
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
          if (!readOnly) action,
        ],
      ),
    );
  }
}
