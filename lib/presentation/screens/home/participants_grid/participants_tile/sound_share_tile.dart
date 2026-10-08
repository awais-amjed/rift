import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/participant_identity.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/sound_share/sound_share_cubit.dart';
import '../../../../../logic/services/participant_roster.dart';
import '../../../../../logic/services/sound_share_label.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/speaking_ring.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/theme_context.dart';
import '../../soundshare/widgets/sound_share_context_menu.dart';
import 'participant_name_badge.dart';
import 'sound_wave_indicator.dart';

/// Somebody's shared sound, as a cell of the voice grid.
///
/// A share with nothing to look at, so the tile is the opposite of the others:
/// no video, no avatar, just whose sound it is and whether it is playing. It
/// earns a cell anyway — a room needs somewhere to see that the music is on,
/// and somewhere to turn it off.
class SoundShareTile extends StatelessWidget {
  final Participant participant;

  const SoundShareTile({super.key, required this.participant});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);
    final identity = participant.identity;
    // Your own share is *not* a local participant: it is a second connection
    // of your own, which reaches you as a remote one. Asking LiveKit whether
    // this is you would say no about the one tile it is you.
    final isOwn = ParticipantIdentity.isShareOf(
      identity,
      context.select<LiveKitCubit, String?>(
        (cubit) => cubit.state.room?.localParticipant?.identity,
      ),
    );
    final userId = ParticipantIdentity.userIdOf(identity);
    final ownerName = context.select<ServerMembersCubit, String>(
      (cubit) => cubit.state.nameFor(userId, participant.name),
    );

    // LiveKit's active-speaker detection covers every connection publishing
    // audio, so a shared track lights up the same way a person talking does.
    final playing = context.select<AppCubit, bool>(
      (cubit) => ParticipantRoster.isSpeaking(
        cubit.state.participants,
        identity,
        fallback: participant.isSpeaking,
      ),
    );
    // What is playing, as the sharer's client published it. Read from the
    // roster rather than off the participant, so it arrives with the track
    // instead of a rebuild later.
    final app = context.select<AppCubit, String>(
      (cubit) =>
          cubit.state.participants
              .where((p) => p.identity == identity)
              .firstOrNull
              ?.shareLabel ??
          '',
    );
    final muted = context.select<AppCubit, bool>(
      (cubit) =>
          cubit
              .state
              .participantSettings[ParticipantIdentity.soundShareSettingsKey(
                identity,
              )]
              ?.muted ??
          false,
    );

    return ContextMenuRegion(
      contextMenu: SoundShareContextMenu(
        identity: identity,
        ownerName: ownerName,
        app: app,
        isOwn: isOwn,
        onStopSharing: () => context.read<SoundShareCubit>().stopSoundShare(),
      ),
      child: SpeakingRing(
        isSpeaking: playing && !muted,
        borderRadius: radius,
        bloom: 2.2,
        child: AnimatedContainer(
          duration: AppMotion.state,
          decoration: BoxDecoration(
            color: theme.callTileBg,
            borderRadius: radius,
            border: Border.all(color: theme.borderElevated),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: SoundWaveIndicator(
                  playing: playing && !muted,
                  color: muted ? theme.textQuaternary : theme.accentBright,
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ParticipantNameBadge(
                    name: soundShareLabel(
                      owner: ownerName,
                      app: app,
                      isOwn: isOwn,
                    ),
                    leadingIcon: Icons.graphic_eq_rounded,
                    isMicEnabled: true,
                    isMuted: false,
                  ),
                ),
              ),
              if (!isOwn)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: IconButton(
                    onPressed: () => context.read<LiveKitCubit>().setMuteFor(
                      ParticipantIdentity.soundShareSettingsKey(identity),
                      !muted,
                    ),
                    tooltip: muted ? 'Unmute sound' : 'Mute sound',
                    icon: Icon(
                      muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      size: K.iconButton,
                    ),
                    color: muted ? theme.textQuaternary : theme.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
