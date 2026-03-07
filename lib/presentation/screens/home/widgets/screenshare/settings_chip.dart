import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// A chip widget for selecting options in screen share settings
class SettingsChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const SettingsChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: active ? CustomColors.primary : themeState.bgTertiary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? CustomColors.primary : themeState.borderPrimary,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : themeState.textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }
}
