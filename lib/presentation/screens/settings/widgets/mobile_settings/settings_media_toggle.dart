import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// Mic or sound, as a labelled 64px control at the top of a phone's settings.
///
/// The switcher's footer has the same two as bare icons — the shortcut. This
/// is the explanation: a word for what each is and which way it is set.
class SettingsMediaToggle extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Off takes the error ink, the same way the dock marks a muted mic.
  final bool isOff;

  final VoidCallback onTap;

  const SettingsMediaToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.isOff,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);
    final ink = isOff ? CustomColors.error : theme.textPrimary;
    return Material(
      color: isOff ? CustomColors.error.withValues(alpha: 0.07) : theme.bgHover,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: theme.borderElevated),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 9,
            children: [
              Icon(icon, size: K.iconLarge, color: ink),
              Text(label, style: AppText.row.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}
