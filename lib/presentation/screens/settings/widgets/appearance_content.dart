import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/segmented_control.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'appearance/palette_card.dart';
import 'section_title.dart';

/// Settings' Appearance tab: light or dark, and the palette.
///
/// Only what the app *looks* like. How it behaves — previews, stream stats,
/// what a flagged picture does, whether a voice switch asks — is General's,
/// which is where somebody goes looking for it.
class AppearanceContent extends StatelessWidget {
  const AppearanceContent({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Theme'),
        const SizedBox(height: 12),
        // One segmented row, not two cards: it is a two-way choice, and the
        // segment is how the app spells those (channel type, sign in / create).
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: SegmentedControl<ThemeMode>(
            value: themeState.themeMode,
            onChanged: context.read<ThemeCubit>().setTheme,
            options: const [
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

        const SizedBox(height: 28),

        const SectionTitle(label: 'Colour palette'),
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
              PaletteCard(
                palette: palette,
                isSelected: themeState.paletteId == palette.id,

                onTap: () => context.read<ThemeCubit>().setPalette(palette.id),
              ),
          ],
        ),
      ],
    );
  }
}
