import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/selectable_surface.dart';
import 'section_title.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text.dart';

class AppearanceContent extends StatelessWidget {
  final ThemeState themeState;

  const AppearanceContent({super.key, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Theme', themeState: themeState),
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

        SectionTitle(label: 'Color Palette', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          'Changes the accent and surface tones across the whole app.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
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
                onTap: () => context.read<ThemeCubit>().setPalette(palette.id),
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
    final preview = themeState.isDarkTheme ? palette.dark : palette.light;

    return SizedBox(
      width: 172,
      child: SelectableSurface(
        selected: isSelected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusCard),
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Swatch row: ground, panel, accent
            Row(
              spacing: 6,
              children: [
                _swatch(preview.bgPrimary, themeState.borderElevated),
                _swatch(preview.bgSecondary, themeState.borderElevated),
                _swatch(preview.primary, Colors.transparent),
                const Spacer(),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: themeState.accentBright,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              palette.name,
              // The name stays plain white in both states — the ring and the
              // check already say which one is chosen, and tinting the name
              // too would make the selected card read as a link.
              style: AppText.row.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: themeState.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              palette.description,
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w400,
                height: 1.4,
                color: themeState.textTertiary,
              ),
            ),
          ],
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
        borderRadius: BorderRadius.circular(K.radiusRow),
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
    return SizedBox(
      width: 130,
      child: SelectableSurface(
        selected: isSelected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusCard),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppText.row.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
