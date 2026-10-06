import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../data/enums/sensitive_content_mode.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../common/segmented_control.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'section_divider.dart';
import 'section_title.dart';
import 'setting_toggle_row.dart';
import 'updates_section.dart';

/// Settings' General tab: how the app behaves, as opposed to what it looks
/// like (Appearance) or how it sounds (Voice & audio).
///
/// Everything here is this device's own and reaches no server.
class GeneralContent extends StatelessWidget {
  const GeneralContent({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Voice channels'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Ask before switching voice channels',
          description:
              'Clicking another voice channel while you are in a call asks '
              'first, so a stray press does not leave the call.',
          value: context.select<AppCubit, bool>(
            (c) => c.state.askBeforeVoiceSwitch,
          ),
          onChanged: context.read<AppCubit>().setAskBeforeVoiceSwitch,
        ),

        const SectionDivider(),

        const SectionTitle(label: 'Link previews'),
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

        const SectionDivider(),

        // Only where there is a title bar to show it in.
        if (HostPlatform.drawsOwnWindowChrome) ...[
          const SectionTitle(label: 'Connection'),
          const SizedBox(height: 12),
          SettingToggleRow(
            title: 'Show "No internet" in the title bar',
            description:
                'Turn this off if it shows while your internet works. A '
                "server that can't be reached is still shown.",
            value: context.select<AppCubit, bool>(
              (c) => c.state.showOfflineChip,
            ),
            onChanged: context.read<AppCubit>().setShowOfflineChip,
          ),
          const SectionDivider(),
        ],

        const SectionTitle(label: 'Streams'),
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

        const SectionDivider(),

        const SectionTitle(label: 'Sensitive content'),
        const SizedBox(height: 4),
        Text(
          'Pictures and messages are checked on this device after they are '
          'decrypted — nothing leaves it. Blur covers what is flagged until '
          'you press it; Hide keeps it covered.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 12),
        // A ceiling, not a width. Three segments spread across a desktop
        // settings pane read as a lost control, but a fixed 360 is wider than
        // a small phone's whole content column and overflowed it.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: K.settingsChoiceWidth),
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

        if (HostPlatform.selfUpdates) ...[
          const SectionDivider(),
          const UpdatesSection(),
        ],
      ],
    );
  }
}
