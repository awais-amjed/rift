import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
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
                style: TextStyle(
                  color: themeState.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
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
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
