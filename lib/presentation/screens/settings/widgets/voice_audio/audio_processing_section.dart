import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';
import 'noise_suppression_choice.dart';

/// How the mic is cleaned up before a call hears it: the noise suppressor,
/// then echo cancellation and gain control. Applied through LiveKit's capture
/// options and, for a noise model, the runner's filter — not by the OS.
class AudioProcessingSection extends StatelessWidget {
  final AppState appState;

  const AudioProcessingSection({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Audio processing'),
        const SizedBox(height: 12),
        NoiseSuppressionChoice(
          value: appState.noiseSuppression,
          onChanged: cubit.setNoiseSuppression,
        ),
        const SizedBox(height: 14),
        SettingToggleRow(
          title: 'Echo cancellation',
          description:
              "Stops other participants' audio, picked up by your mic, "
              'from echoing back to them.',
          value: appState.echoCancellation,
          onChanged: cubit.setEchoCancellation,
        ),
        const SizedBox(height: 14),
        SettingToggleRow(
          title: 'Automatic gain control',
          description:
              'Evens out your mic level as you move nearer to or further '
              'from the mic.',
          value: appState.autoGainControl,
          onChanged: cubit.setAutoGainControl,
        ),
      ],
    );
  }
}
