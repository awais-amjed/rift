import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/segmented_control.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'appearance/palette_card.dart';
import 'section_divider.dart';
import 'section_title.dart';

/// Settings' Appearance tab: light or dark, and the palette.
///
/// Only what the app *looks* like. How it behaves — previews, stream stats,
/// what a flagged picture does, whether a voice switch asks — is General's,
/// which is where somebody goes looking for it.
class AppearanceContent extends StatelessWidget {
  const AppearanceContent({super.key});

  static const double _gap = 12;

  /// A palette card's width in a row [available] wide.
  static double _cardWidth(double available) {
    if (!available.isFinite ||
        available >= PaletteCard.defaultWidth * 2 + _gap) {
      return PaletteCard.defaultWidth;
    }
    final half = (available - _gap) / 2;
    return half >= PaletteCard.minWidth ? half : available;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Theme'),
        const SizedBox(height: 12),
        // One segmented row, not three cards: it is a small closed choice, and
        // the segment is how the app spells those (channel type, sign in /
        // create).
        //
        // The value is the *preference*, read from the cubit rather than from
        // `context.theme` — the theme's own `themeMode` is whichever
        // brightness is being drawn, which is never System and would leave the
        // third segment permanently unselected.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: K.settingsChoiceWidth),
          child: SegmentedControl<ThemeMode>(
            value: context.watch<ThemeCubit>().state.themeMode,
            onChanged: context.read<ThemeCubit>().setTheme,
            options: const [
              SegmentOption(
                value: ThemeMode.system,
                label: 'System',
                icon: Icons.brightness_auto_outlined,
              ),
              SegmentOption(
                value: ThemeMode.dark,
                label: 'Dark',
                icon: Icons.dark_mode_outlined,
              ),
              SegmentOption(
                value: ThemeMode.light,
                label: 'Light',
                icon: Icons.light_mode_outlined,
              ),
            ],
          ),
        ),

        const SectionDivider(),

        const SectionTitle(label: 'Color palette'),
        const SizedBox(height: 4),
        Text(
          'Changes the accent and surface tones across the whole app.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 12),
        // Fixed-width cards while two or more fit. On a phone two did not
        // quite, and the four stood in a column with the rest of the row
        // empty; there they share the row two to a line instead.
        LayoutBuilder(
          builder: (context, constraints) {
            final width = _cardWidth(constraints.maxWidth);
            return Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [
                for (final palette in AppPalette.all)
                  PaletteCard(
                    palette: palette,
                    isSelected: themeState.paletteId == palette.id,
                    width: width,
                    onTap: () =>
                        context.read<ThemeCubit>().setPalette(palette.id),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
