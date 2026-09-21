import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import 'participant_volume_slider.dart';

/// The local volume slider at the foot of a participant's context menu:
/// a small-caps heading and readout over a [ParticipantVolumeSlider].
///
/// Local to *you* — it changes how loud they are in your ears and nothing
/// else.
class ParticipantVolumeControl extends StatelessWidget {
  /// A live LiveKit identity, or a bare user id when they aren't connected —
  /// [LiveKitCubit.setParticipantVolume] accepts either and stores the setting
  /// per user.
  final String target;

  final bool isMuted;
  final double volume;

  /// Where the new volume goes. Defaults to the participant's own — a shared
  /// track passes its own, so that turning the music down does not turn its
  /// owner down with it.
  final ValueChanged<double>? onChanged;

  const ParticipantVolumeControl({
    super.key,
    required this.target,
    required this.isMuted,
    required this.volume,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'VOLUME',
                    style: AppText.sectionLabel.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                  Text(
                    ParticipantVolumeSlider.readout(
                      isMuted: isMuted,
                      volume: volume,
                    ),
                    style: AppText.chip.copyWith(
                      color: themeState.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ParticipantVolumeSlider(
                target: target,
                isMuted: isMuted,
                volume: volume,
                onChanged: onChanged,
              ),
            ],
          ),
        );
      },
    );
  }
}
