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
        // One segmented row, not two cards: it is a two-way choice, and the
        // segment is how the app spells those (channel type, sign in / create).
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Row(
            spacing: 8,
            children: [
              _ModeSegment(
                label: 'Dark',
                icon: Icons.dark_mode_outlined,
                selected: themeState.isDarkTheme,
                onTap: () =>
                    context.read<ThemeCubit>().setTheme(ThemeMode.dark),
              ),
              _ModeSegment(
                label: 'Light',
                icon: Icons.light_mode_outlined,
                selected: themeState.isLightTheme,
                onTap: () =>
                    context.read<ThemeCubit>().setTheme(ThemeMode.light),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        SectionTitle(label: 'Colour palette', themeState: themeState),
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

/// One half of the Dark / Light segment.
class _ModeSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SelectableSurface(
        selected: selected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusRow),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 7,
          children: [
            Icon(icon, size: 16),
            Text(label, style: selected ? AppText.row : AppText.rowQuiet),
          ],
        ),
      ),
    );
  }
}

/// A palette, previewed as the piece of UI it actually changes: a channel row
/// in that palette's own surfaces, selected in its accent, with an unread
/// badge. Three swatches said which colours a palette had; this says what
/// the app looks like in it.
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
    // The preview is drawn in the palette's own colours for the current
    // brightness, whichever palette is active.
    final preview = themeState.isDarkTheme ? palette.dark : palette.light;

    return SizedBox(
      width: 172,
      child: SelectableSurface(
        selected: isSelected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusCard),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PalettePreview(colors: preview),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    palette.name,
                    // The name stays plain in both states — the border and the
                    // check already say which one is chosen, and tinting the
                    // name too would make the selected card read as a link.
                    style: (isSelected ? AppText.strong : AppText.row).copyWith(
                      color: themeState.textPrimary,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: themeState.accentBright,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              palette.description,
              style: AppText.secondary.copyWith(
                height: 1.4,
                color: themeState.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A miniature of the sidebar: the panel surface on the canvas, one channel
/// row selected in the accent, one at rest with a count.
class _PalettePreview extends StatelessWidget {
  final PaletteColors colors;

  const _PalettePreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: colors.borderElevated),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.bgSecondary,
          borderRadius: BorderRadius.circular(K.radiusRow - 2),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          spacing: 3,
          children: [
            _PreviewRow(label: 'general', selected: true, colors: colors),
            _PreviewRow(label: 'design', count: 2, colors: colors),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final bool selected;
  final int? count;
  final PaletteColors colors;

  const _PreviewRow({
    required this.label,
    required this.colors,
    this.selected = false,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? colors.channelActiveBg : null,
        borderRadius: BorderRadius.circular(K.radiusRow - 4),
      ),
      child: Row(
        spacing: 5,
        children: [
          Icon(
            Icons.tag,
            size: 11,
            color: selected ? colors.accentBright : colors.textQuaternary,
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.chip.copyWith(
                color: selected
                    ? colors.channelActiveText
                    : colors.textSecondary,
              ),
            ),
          ),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(K.radiusPill),
              ),
              child: Text(
                '$count',
                style: AppText.badge.copyWith(color: colors.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}
