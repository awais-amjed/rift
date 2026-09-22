import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Header section for the screen share settings dialog
class SettingsDialogHeader extends StatelessWidget {
  final VoidCallback onClose;

  const SettingsDialogHeader({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: themeState.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(K.radiusRow),
          ),
          child: Icon(Icons.monitor, size: 18, color: themeState.primary),
        ),
        const SizedBox(width: 10),
        Text(
          'Screen share settings',
          style: AppText.dialogTitle.copyWith(color: themeState.textPrimary),
        ),
        const Spacer(),
        IconButton(
          onPressed: onClose,
          icon: Icon(Icons.close, size: 18, color: themeState.textQuaternary),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
            ),
          ),
        ),
      ],
    );
  }
}
