import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../common/volume_slider.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';

/// The soundboard, from the listening end.
///
/// The same two controls the picker carries at its foot, findable when there
/// is no call open — which is when somebody decides they have had enough of
/// airhorns, rather than in the middle of one.
///
/// Neither of them reaches a server. A clip is played by each listener out of
/// their own speakers, so this is the whole of the decision; turning somebody
/// *particular* down is on their profile, or in their right-click menu.
///
/// The mute is everyone *else*: a clip you pressed is one you asked for, and
/// you should hear what the room is about to. Being deafened is the switch
/// that silences all of it.
class SoundboardSection extends StatelessWidget {
  final AppState appState;

  const SoundboardSection({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Soundboard'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Mute everyone else\'s soundboard',
          description:
              'Stop playing the clips other people press. Your own still '
              'play, the room still hears them, and nobody else is affected.',
          value: appState.soundboardMuted,
          onChanged: context.read<AppCubit>().setSoundboardMuted,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'VOLUME',
              style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
            ),
            const Spacer(),
            Text(
              appState.soundboardMuted
                  ? '—'
                  : '${(appState.soundboardVolume * 100).round()}%',
              style: AppText.chip.copyWith(color: theme.textSecondary),
            ),
          ],
        ),
        VolumeSlider(
          value: appState.soundboardMuted ? 0 : appState.soundboardVolume,
          onChanged: appState.soundboardMuted
              ? null
              : context.read<AppCubit>().setSoundboardVolume,
        ),
      ],
    );
  }
}
