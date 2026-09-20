import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../common/app_switch.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../sidebar/widgets/participant_volume_control.dart';
import 'profile_section.dart';

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
  final String userId;

  const ProfileLocalAudio({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final setting = context.watch<AppCubit>().state.participantSettings[userId];
    final muted = setting?.muted ?? false;
    final volume = setting?.volume ?? 1.0;

    return ProfileSection(
      label: 'Your audio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mute for me',
                      style: AppText.row.copyWith(
                        color: themeState.textSecondary,
                      ),
                    ),
                    Text(
                      'They stay audible to everyone else.',
                      style: AppText.secondary.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppSwitch(
                value: muted,
                onChanged: (next) => context
                    .read<LiveKitCubit>()
                    .setParticipantMute(userId, next),
              ),
            ],
          ),
          // The menu's own slider, unchanged: the percentage, the em dash
          // while muted and the disabled track are all decisions that were
          // made once and should not be made twice.
          ParticipantVolumeControl(
            target: userId,
            isMuted: muted,
            volume: volume,
          ),
        ],
      ),
    );
  }
}
