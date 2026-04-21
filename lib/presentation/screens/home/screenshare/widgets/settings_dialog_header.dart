import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// Header section for the screen share settings dialog
class SettingsDialogHeader extends StatelessWidget {
  final VoidCallback onClose;

  const SettingsDialogHeader({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CustomColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.monitor,
                size: 18,
                color: CustomColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Screen Share Settings',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: themeState.textPrimary,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: onClose,
              icon: Icon(
                Icons.close,
                size: 18,
                color: themeState.textQuaternary,
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
