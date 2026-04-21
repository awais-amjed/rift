import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';

class AppearanceContent extends StatelessWidget {
  final ThemeState themeState;

  const AppearanceContent({super.key, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: themeState.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ThemeCard(
              label: 'Dark',
              icon: Icons.dark_mode_outlined,
              isSelected: themeState.isDarkTheme,
              themeState: themeState,
              onTap: () => context.read<ThemeCubit>().setTheme(ThemeMode.dark),
            ),
            const SizedBox(width: 12),
            ThemeCard(
              label: 'Light',
              icon: Icons.light_mode_outlined,
              isSelected: themeState.isLightTheme,
              themeState: themeState,
              onTap: () => context.read<ThemeCubit>().setTheme(ThemeMode.light),
            ),
          ],
        ),
      ],
    );
  }
}

class ThemeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final ThemeState themeState;
  final VoidCallback onTap;

  const ThemeCard({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isSelected ? themeState.channelActiveBorder : themeState.borderPrimary;
    final bgColor =
        isSelected ? themeState.channelActiveBg : themeState.bgTertiary;
    final textColor =
        isSelected ? themeState.channelActiveText : themeState.textSecondary;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 110,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: textColor),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

