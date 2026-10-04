import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/call_volume.dart';
import '../../../../common/volume_slider.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

/// How loud every call is here, on top of each person's own volume, which
/// stays on their profile and in their right-click menu. Calls only: Rift's
/// own sounds and the soundboard have their volumes further down.
class OutputVolumeSection extends StatelessWidget {
  const OutputVolumeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final volume = context.select<AppCubit, double>(
      (cubit) => cubit.state.outputVolume,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Call volume'),
        const SizedBox(height: 4),
        Text(
          'Everyone in a call, on top of the volume you set for each person.',
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: VolumeSlider(
                value: volume,
                max: CallVolume.max,
                onChanged: context.read<AppCubit>().setOutputVolume,
              ),
            ),
            // Wide enough for "200%", so dragging never shifts the track.
            SizedBox(
              width: 40,
              child: Text(
                '${(volume * 100).round()}%',
                textAlign: TextAlign.right,
                style: AppText.meta.copyWith(color: theme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
