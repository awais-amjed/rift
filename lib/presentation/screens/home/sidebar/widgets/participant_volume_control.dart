import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';

/// The local volume slider at the foot of a participant's context menu.
///
/// Local to *you* — it changes how loud they are in your ears and nothing
/// else. Disabled while they're locally muted, where a percentage would be a
/// number with no effect; the readout shows an em dash instead of 0%, which
/// would look like a volume you'd chosen.
class ParticipantVolumeControl extends StatelessWidget {
  /// A live LiveKit identity, or a bare user id when they aren't connected —
  /// [LiveKitCubit.setParticipantVolume] accepts either and stores the setting
  /// per user.
  final String target;

  final bool isMuted;
  final double volume;

  const ParticipantVolumeControl({
    super.key,
    required this.target,
    required this.isMuted,
    required this.volume,
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
                    isMuted ? '—' : '${(volume * 100).round()}%',
                    style: AppText.chip.copyWith(
                      color: themeState.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: themeState.primary,
                  inactiveTrackColor: themeState.bgActive,
                  thumbColor: themeState.primary,
                ),
                child: Slider(
                  value: isMuted ? 0 : volume,
                  onChanged: isMuted
                      ? null
                      : (value) => context
                            .read<LiveKitCubit>()
                            .setParticipantVolume(target, value),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
