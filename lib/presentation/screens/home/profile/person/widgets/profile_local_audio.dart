import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/participant_identity.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../common/app_switch.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../sidebar/widgets/participant_volume_slider.dart';
import 'profile_section.dart';
import 'profile_setting_row.dart';

/// How loud this person is **in your ears**, and nothing else.
///
/// Until now the only way to reach either control was to right-click a roster
/// row, which is not a thing anybody discovers. Both settings are stored per
/// user and re-applied the next time you share a voice channel, so they are
/// worth setting whether or not the person is in a call right now — which is
/// why this section is always here rather than only while they are connected.
///
/// The label says "your" because the button below it in the moderation
/// section says "server", and those two words are the whole difference
/// between a preference and an act of moderation.
class ProfileLocalAudio extends StatelessWidget {
  /// Short enough to sit beside its label like a switch does, long enough
  /// that a small drag is a small change.
  static const double _sliderWidth = 140;

  final String userId;

  const ProfileLocalAudio({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final settings = context.watch<AppCubit>().state.participantSettings;
    final setting = settings[userId];
    final muted = setting?.muted ?? false;
    final volume = setting?.volume ?? 1.0;
    // A third setting of their own, stored under its own key: somebody whose
    // airhorn is too loud has not said anything wrong.
    final soundboardMuted =
        settings[ParticipantIdentity.soundboardSettingsKey(userId)]?.muted ??
        false;

    return ProfileSection(
      label: 'Your audio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ProfileSettingRow(
            title: 'Mute for me',
            hint: 'They stay audible to everyone else.',
            control: AppSwitch(
              value: muted,
              onChanged: (next) =>
                  context.read<LiveKitCubit>().setParticipantMute(userId, next),
            ),
          ),
          ProfileSettingRow(
            title: 'Mute their soundboard',
            hint:
                'Clips they press stop playing here. Their voice is not '
                'affected.',
            control: AppSwitch(
              value: soundboardMuted,
              onChanged: (next) =>
                  context.read<AppCubit>().setSoundboardMutedFor(userId, next),
            ),
          ),
          ProfileSettingRow(
            title: 'Volume',
            hint: 'Only changes it for you.',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _sliderWidth,
                  child: ParticipantVolumeSlider(
                    target: userId,
                    isMuted: muted,
                    volume: volume,
                  ),
                ),
                // Wide enough for "100%", so dragging never shifts the track.
                SizedBox(
                  width: 40,
                  child: Text(
                    ParticipantVolumeSlider.readout(
                      isMuted: muted,
                      volume: volume,
                    ),
                    textAlign: TextAlign.right,
                    style: AppText.meta.copyWith(
                      color: themeState.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
