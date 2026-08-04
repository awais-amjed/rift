import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_switch.dart';
import '../../../theme/app_text.dart';

/// A titled description with a trailing switch — the standard layout for a
/// boolean setting.
///
/// A null [onChanged] disables the switch, which is how a platform-specific
/// setting stays visible (with a description explaining why) on platforms
/// that cannot offer it.
class SettingToggleRow extends StatelessWidget {
  final ThemeState themeState;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingToggleRow({
    super.key,
    required this.themeState,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.row.copyWith(color: themeState.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppText.secondary.copyWith(
                  color: themeState.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Dimmed rather than hidden — a setting this platform can't offer
        // still shows its state, with the description saying why.
        Opacity(
          opacity: onChanged == null ? 0.5 : 1,
          child: AppSwitch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}
