import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/mic_volume.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import 'volume_row.dart';

/// How loud this microphone is sent, in calls and in the mic test. Shown only
/// where Rift can set it ([MicVolume.adjustable]).
class InputVolumeSection extends StatelessWidget {
  const InputVolumeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final volume = context.select<AppCubit, double>(
      (cubit) => cubit.state.inputVolume,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Mic volume'),
        const SizedBox(height: 4),
        Text(
          'Turn it up if people hear you quietly.',
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
        const SizedBox(height: 8),
        VolumeRow(
          value: volume,
          max: MicVolume.max,
          onChanged: context.read<AppCubit>().setInputVolume,
        ),
      ],
    );
  }
}
