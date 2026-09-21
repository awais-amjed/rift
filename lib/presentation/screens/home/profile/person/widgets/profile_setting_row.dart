import 'package:flutter/material.dart';

import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One setting in a profile: what it is and a line on what it does, with its
/// control at the end.
///
/// Every setting in the section takes this shape, a slider as much as a
/// switch. When the volume sat under the switches as a full-width bar with a
/// heading of its own, it read as a different kind of thing.
class ProfileSettingRow extends StatelessWidget {
  final String title;
  final String hint;
  final Widget control;

  const ProfileSettingRow({
    super.key,
    required this.title,
    required this.hint,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.row.copyWith(color: themeState.textSecondary),
              ),
              Text(
                hint,
                style: AppText.secondary.copyWith(
                  color: themeState.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        control,
      ],
    );
  }
}
