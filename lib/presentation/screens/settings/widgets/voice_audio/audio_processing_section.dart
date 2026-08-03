import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';

/// The three mic-processing switches. Cross-platform — these are applied by
/// LiveKit's capture options rather than by the OS.
class AudioProcessingSection extends StatelessWidget {
  final ThemeState themeState;
  final AppState appState;

  const AudioProcessingSection({
    super.key,
    required this.themeState,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(label: 'Audio Processing', themeState: themeState),
        const SizedBox(height: 12),
        SettingToggleRow(
          themeState: themeState,
          title: 'Noise suppression',
          description:
              'Filters out steady background noise like fans, keyboards, '
              'and hum before it reaches the call.',
          value: appState.noiseSuppression,
          onChanged: cubit.setNoiseSuppression,
        ),
        const SizedBox(height: 14),
        SettingToggleRow(
          themeState: themeState,
          title: 'Echo cancellation',
          description:
              "Stops other participants' audio, picked up by your mic, "
              'from echoing back to them.',
          value: appState.echoCancellation,
          onChanged: cubit.setEchoCancellation,
        ),
        const SizedBox(height: 14),
        SettingToggleRow(
          themeState: themeState,
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
