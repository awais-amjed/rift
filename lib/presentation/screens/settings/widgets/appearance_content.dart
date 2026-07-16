import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_palette.dart';

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

        const SizedBox(height: 28),

        Text(
          'Color Palette',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: themeState.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Changes the accent and surface tones across the whole app.',
          style: TextStyle(fontSize: 12, color: themeState.textTertiary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final palette in AppPalette.all)
              _PaletteCard(
                palette: palette,
                isSelected: themeState.paletteId == palette.id,
                themeState: themeState,
                onTap: () =>
                    context.read<ThemeCubit>().setPalette(palette.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _PaletteCard extends StatelessWidget {
  final AppPalette palette;
  final bool isSelected;
  final ThemeState themeState;
  final VoidCallback onTap;

  const _PaletteCard({
    required this.palette,
    required this.isSelected,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Preview swatches always show the palette's own colors for the current
    // brightness, regardless of the active palette.
    final preview =
        themeState.isDarkTheme ? palette.dark : palette.light;

    final borderColor =
        isSelected ? themeState.channelActiveBorder : themeState.borderPrimary;

    return Material(
      color: themeState.bgTertiary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 148,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Swatch row: ground, panel, accent
              Row(
                children: [
                  _swatch(preview.bgPrimary, themeState.borderPrimary),
                  const SizedBox(width: 6),
                  _swatch(preview.bgSecondary, themeState.borderPrimary),
                  const SizedBox(width: 6),
                  _swatch(preview.primary, Colors.transparent),
                  const Spacer(),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: themeState.primary,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                palette.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: themeState.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                palette.description,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: themeState.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(Color color, Color border) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
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

