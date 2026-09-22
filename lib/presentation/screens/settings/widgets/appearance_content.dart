import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/sensitive_content_mode.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/segmented_control.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'appearance/palette_card.dart';
import 'section_title.dart';
import 'setting_toggle_row.dart';

class AppearanceContent extends StatelessWidget {
  const AppearanceContent({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Theme'),
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

        SectionTitle(label: 'Colour palette'),
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

        const SizedBox(height: 28),

        SectionTitle(label: 'Link previews'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Preview links you send',
          description:
              'When you paste a link, this device fetches the page once and '
              'sends its title and picture inside the encrypted message. '
              'Nobody reading it ever touches the site.',
          value: context.select<AppCubit, bool>(
            (c) => c.state.linkPreviewsEnabled,
          ),
          onChanged: (v) => context.read<AppCubit>().setLinkPreviewsEnabled(v),
        ),

        const SizedBox(height: 28),

        SectionTitle(label: 'Streams'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Detailed stream stats',
          description:
              'Shows bitrate, ping, jitter, packet loss and codec over a '
              'stream you are watching. The resolution and frame rate are '
              'always shown beside the sharer\'s name.',
          value: context.select<AppCubit, bool>((c) => c.state.showStreamStats),
          onChanged: (v) => context.read<AppCubit>().setShowStreamStats(v),
        ),

        const SizedBox(height: 28),

        SectionTitle(label: 'Sensitive content'),
        const SizedBox(height: 4),
        Text(
          'Pictures and messages are checked on this device after they are '
          'decrypted — nothing leaves it. Blur covers what is flagged until '
          'you tap; Hide keeps it covered.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 12),
        // A ceiling, not a width. Three segments spread across a desktop
        // settings pane read as a lost control, but a fixed 360 is wider than
        // a small phone's whole content column and overflowed it.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SegmentedControl<SensitiveContentMode>(
            value: context.select<AppCubit, SensitiveContentMode>(
              (c) => c.state.sensitiveContentMode,
            ),
            onChanged: (mode) =>
                context.read<AppCubit>().setSensitiveContentMode(mode),
            options: [
              for (final mode in SensitiveContentMode.values)
                SegmentOption(value: mode, label: mode.label),
            ],
          ),
        ),
      ],
    );
  }
}
