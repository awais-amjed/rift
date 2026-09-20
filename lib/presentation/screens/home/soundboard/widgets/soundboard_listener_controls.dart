import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../common/app_switch.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// How loud everybody else's clips are **here**.
///
/// At the foot of the picker rather than buried in settings, because the
/// moment somebody wants this is the moment a clip has just gone off. Nothing
/// it changes is sent anywhere: a press is played locally by each listener,
/// so this is the whole of the decision.
class SoundboardListenerControls extends StatelessWidget {
  const SoundboardListenerControls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = context.select<AppCubit, bool>(
      (cubit) => cubit.state.soundboardMuted,
    );
    final volume = context.select<AppCubit, double>(
      (cubit) => cubit.state.soundboardVolume,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Mute everyone else',
                style: AppText.row.copyWith(color: theme.textSecondary),
              ),
            ),
            AppSwitch(
              value: muted,
              onChanged: context.read<AppCubit>().setSoundboardMuted,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Their clips stop playing here. Yours still do, and the room '
          'still hears them.',
          style: AppText.rowQuiet.copyWith(color: theme.textQuaternary),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'VOLUME',
              style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
            ),
            const Spacer(),
            Text(
              muted ? '—' : '${(volume * 100).round()}%',
              style: AppText.chip.copyWith(color: theme.textSecondary),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: theme.primary,
            inactiveTrackColor: theme.bgActive,
            thumbColor: theme.primary,
          ),
          child: Slider(
            value: muted ? 0 : volume,
            onChanged: muted
                ? null
                : context.read<AppCubit>().setSoundboardVolume,
          ),
        ),
      ],
    );
  }
}
