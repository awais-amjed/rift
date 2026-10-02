import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/app/app_cubit.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'volume_slider.dart';

/// This device's soundboard volume: the label, the figure and the slider.
///
/// It stays live while everyone else is muted, because the mute never covers
/// your own clips ([SoundboardVolume]). They go on playing at this volume. It
/// used to grey out and read 0 while your own clips played at 60 %, with no
/// way to turn them down (F-7). Shared by the soundboard picker and Settings
/// so the two cannot disagree again.
class SoundboardVolumeControl extends StatelessWidget {
  const SoundboardVolumeControl({super.key});

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
            Text(
              'VOLUME',
              style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
            ),
            const Spacer(),
            Text(
              '${(volume * 100).round()}%',
              style: AppText.chip.copyWith(color: theme.textSecondary),
            ),
          ],
        ),
        VolumeSlider(
          value: volume,
          onChanged: context.read<AppCubit>().setSoundboardVolume,
        ),
        if (muted)
          Text(
            'Only your own clips play now, at this volume.',
            style: AppText.rowQuiet.copyWith(color: theme.textQuaternary),
          ),
      ],
    );
  }
}
