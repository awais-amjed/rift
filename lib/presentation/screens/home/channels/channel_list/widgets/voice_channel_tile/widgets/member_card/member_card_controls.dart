import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import '../../../../../../../../../data/participant_identity.dart';
import '../../../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../../logic/helper_methods.dart';
import '../../../../../../controls/widgets/control_button.dart';
import '../../../../../../sidebar/widgets/participant_volume_control.dart';

/// The quick controls on a member card: the few things the person's
/// right-click menu offers that are worth one press — how loud they are, and
/// whether you hear them, they hear you, or anybody does.
///
/// The same calls the menu makes, so the two can never disagree. For your own
/// row it is your own microphone and headphones instead, as in the dock.
class MemberCardControls extends StatelessWidget {
  final String userId;

  const MemberCardControls({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final me = context.select<ServerCubit, String?>(
      (cubit) => cubit.state.selectedServer?.user?.id,
    );
    if (userId == me) return const _OwnControls();
    return _TheirControls(userId: userId);
  }
}

/// Your own mute and deafen, exactly as the dock draws them.
class _OwnControls extends StatelessWidget {
  const _OwnControls();

  @override
  Widget build(BuildContext context) {
    final lk = context.watch<LiveKitCubit>().state;
    final micOn = lk.isMicOn;
    final deafened = lk.isDeafenedEffective;
    return Row(
      spacing: 6,
      children: [
        Expanded(
          child: ControlButton(
            dense: true,
            icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            tooltip: lk.isModerated
                ? 'Muted by a moderator'
                : (micOn ? 'Mute' : 'Unmute'),
            isError: !micOn,
            onTap: () => context.read<LiveKitCubit>().toggleMicrophone(),
          ),
        ),
        Expanded(
          child: ControlButton(
            dense: true,
            icon: deafened ? Icons.headset_off_rounded : Icons.headset_rounded,
            tooltip: lk.isServerDeafened
                ? 'Deafened by a moderator'
                : (deafened ? 'Undeafen' : 'Deafen'),
            isError: deafened,
            onTap: () => context.read<LiveKitCubit>().toggleDeafen(),
          ),
        ),
      ],
    );
  }
}

/// Somebody else: their volume for you, then a row of toggles, each red while
/// it is on.
class _TheirControls extends StatelessWidget {
  final String userId;

  const _TheirControls({required this.userId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppCubit>().state;
    final setting = app.participantSettings[userId];
    final muted = setting?.muted ?? false;
    final soundboardMuted =
        app
            .participantSettings[ParticipantIdentity.soundboardSettingsKey(
              userId,
            )]
            ?.muted ??
        false;
    final voiceHidden = app.voiceHiddenFrom.contains(userId);
    // Their moderation state only reaches us from a call we share with them,
    // the same rule the menu keeps — anywhere else it would be a guess.
    final live = app.participants
        .where((p) => p.userId == userId && !p.isShare)
        .firstOrNull;
    final permissions = context.select<ServerCubit, bool>((cubit) {
      final mine = cubit.state.myPermissions;
      return (mine?.isServerAdmin ?? false) ||
          (mine?.isChannelManager ?? false);
    });
    final member = context.select<ServerMembersCubit, ({bool bot, bool admin})>(
      (cubit) {
        final row = cubit.state.byId[userId];
        return (
          bot: row?.isBot ?? false,
          admin: row?.permissions.isServerAdmin ?? false,
        );
      },
    );
    final isBot = member.bot;
    // The server refuses to moderate an admin (`cannot_moderate_admin`), so
    // the buttons are not offered for one.
    final moderates = permissions && live != null && !member.admin;
    final livekit = context.read<LiveKitCubit>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        ParticipantVolumeControl(
          target: userId,
          isMuted: muted,
          volume: setting?.volume ?? 1.0,
          padding: EdgeInsets.zero,
        ),
        Row(
          spacing: 6,
          children: [
            Expanded(
              child: ControlButton(
                dense: true,
                icon: Icons.volume_off_rounded,
                tooltip: muted ? 'Unmute for you' : 'Mute for you',
                isError: muted,
                onTap: () => livekit.setParticipantMute(userId, !muted),
              ),
            ),
            // A bot has no soundboard to turn down.
            if (!isBot)
              Expanded(
                child: ControlButton(
                  dense: true,
                  icon: Icons.graphic_eq_rounded,
                  tooltip: soundboardMuted
                      ? 'Unmute their soundboard'
                      : 'Mute their soundboard',
                  isError: soundboardMuted,
                  onTap: () => context.read<AppCubit>().setSoundboardMutedFor(
                    userId,
                    !soundboardMuted,
                  ),
                ),
              ),
            Expanded(
              child: ControlButton(
                dense: true,
                icon: Icons.voice_over_off_rounded,
                tooltip: voiceHidden
                    ? 'Stop hiding my voice'
                    : 'Hide my voice from them',
                isError: voiceHidden,
                onTap: () => livekit.setVoiceHiddenFrom(userId, !voiceHidden),
              ),
            ),
            if (moderates) ...[
              Expanded(
                child: ControlButton(
                  dense: true,
                  icon: Icons.mic_off_rounded,
                  tooltip: live.isServerMuted ? 'Server unmute' : 'Server mute',
                  isError: live.isServerMuted,
                  onTap: () => _moderate(
                    livekit.moderateParticipant(
                      participantIdentity: userId,
                      muted: !live.isServerMuted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ControlButton(
                  dense: true,
                  icon: Icons.headset_off_rounded,
                  tooltip: live.isServerDeafened
                      ? 'Server undeafen'
                      : 'Server deafen',
                  isError: live.isServerDeafened,
                  onTap: () => _moderate(
                    livekit.moderateParticipant(
                      participantIdentity: userId,
                      deafened: !live.isServerDeafened,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// A refusal would otherwise look like a button that does nothing.
  Future<void> _moderate(Future<bool> call) async {
    if (await call) return;
    HelperMethods.showToast(
      title: 'Could not change that',
      description: 'The server refused. Try again in a moment.',
      type: ToastificationType.error,
    );
  }
}
