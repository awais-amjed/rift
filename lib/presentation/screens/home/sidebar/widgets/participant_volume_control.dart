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

  /// Where the new volume goes. Defaults to the participant's own — a shared
  /// track passes its own, so that turning the music down does not turn its
  /// owner down with it.
  final ValueChanged<double>? onChanged;

  /// Laid out as one more setting in a list of them — a profile's "Your
  /// audio" — rather than as the foot of a menu: no inset of its own, since
  /// the section already has one, and a row's title where a menu has its
  /// small-caps label, so it reads like the switches above it.
  final bool asSetting;

  const ParticipantVolumeControl({
    super.key,
    required this.target,
    required this.isMuted,
    required this.volume,
    this.onChanged,
    this.asSetting = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Padding(
          padding: asSetting
              ? const EdgeInsets.only(top: 12)
              : const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  asSetting
                      ? Text(
                          'Volume',
                          style: AppText.row.copyWith(
                            color: themeState.textSecondary,
                          ),
                        )
                      : Text(
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
                  // Flutter pads the track by the overlay's radius on each
                  // side, which left it well short of the label and the
                  // percentage above it. The thumb's own radius is all it
                  // needs: at either end, the thumb's edge meets theirs.
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  value: isMuted ? 0 : volume,
                  onChanged: isMuted
                      ? null
                      : (value) {
                          final handler = onChanged;
                          if (handler != null) {
                            handler(value);
                            return;
                          }
                          context.read<LiveKitCubit>().setParticipantVolume(
                            target,
                            value,
                          );
                        },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
