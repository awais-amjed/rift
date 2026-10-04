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
  final String userId;

  const ProfileLocalAudio({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppCubit>().state.participantSettings;
    final setting = settings[userId];
    final muted = setting?.muted ?? false;
    final volume = setting?.volume ?? 1.0;
    // A third setting of their own, stored under its own key: somebody whose
    // airhorn is too loud has not said anything wrong.
    final soundboard =
        settings[ParticipantIdentity.soundboardSettingsKey(userId)];
    final soundboardMuted = soundboard?.muted ?? false;

    return ProfileSection(
      label: 'Your audio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          _volumeRow(
            context,
            title: 'Volume',
            hint: 'Only changes it for you.',
            target: userId,
            muted: muted,
            volume: volume,
          ),
          ProfileSettingRow(
            title: 'Mute for me',
            hint: 'They stay audible to everyone else.',
            control: AppSwitch(
              value: muted,
              onChanged: (next) =>
                  context.read<LiveKitCubit>().setParticipantMute(userId, next),
            ),
          ),
          _volumeRow(
            context,
            title: 'Soundboard volume',
            hint: 'Their clips, only for you.',
            target: userId,
            muted: soundboard?.muted ?? false,
            volume: soundboard?.volume ?? 1.0,
            max: 1.0,
            onChanged: (value) =>
                context.read<AppCubit>().setSoundboardVolumeFor(userId, value),
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
        ],
      ),
    );
  }

  /// A volume: its name and what it means, then the track across the width
  /// it has.
  ///
  /// The slider used to sit at the end of the row like a switch does. In a
  /// profile column it took half the line, and every label in the section
  /// wrapped around it — "Soundboard volume" over two lines with its
  /// sentence broken into three. A track is the one control here that wants
  /// the width, so it gets the line to itself.
  Widget _volumeRow(
    BuildContext context, {
    required String title,
    required String hint,
    required String target,
    required bool muted,
    required double volume,
    ValueChanged<double>? onChanged,
    double? max,
  }) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.row.copyWith(color: themeState.textSecondary),
        ),
        Text(
          hint,
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        Row(
          children: [
            Expanded(
              child: ParticipantVolumeSlider(
                target: target,
                isMuted: muted,
                volume: volume,
                onChanged: onChanged,
                max: max,
              ),
            ),
            // Wide enough for "200%", so dragging never shifts the track.
            SizedBox(
              width: 40,
              child: Text(
                ParticipantVolumeSlider.readout(isMuted: muted, volume: volume),
                textAlign: TextAlign.right,
                style: AppText.meta.copyWith(color: themeState.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
