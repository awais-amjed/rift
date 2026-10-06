import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/mic_volume.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'volume_row.dart';

/// How loud this microphone is sent, in calls and in the mic test. It sits
/// right above the mic test, so it can be set while hearing the result.
/// Shown only where Rift can set it ([MicVolume.adjustable]).
class MicVolumeControl extends StatelessWidget {
  const MicVolumeControl({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final volume = context.select<AppCubit, double>(
      (cubit) => cubit.state.inputVolume,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mic volume',
          style: AppText.row.copyWith(color: theme.textPrimary),
        ),
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
