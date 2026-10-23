import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../data/enums/server_permission.dart';
import '../../../../../../../../../data/participant_identity.dart';
import '../../../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../common/server_scope.dart';
import '../../../../../../controls/widgets/control_button.dart';
import '../../../../../../sidebar/widgets/participant_volume_control.dart';

/// Over the widget budget and one job: a member card's quick controls, yours or
/// theirs.
///
/// The quick controls on a member card: the few things the person's
/// right-click menu offers that are worth one press — how loud they are, and
/// whether you hear them, they hear you, or anybody does.
///
/// The same calls the menu makes, so the two can never disagree. For your own
/// row it is your own microphone and headphones instead, as in the dock.
class MemberCardControls extends StatelessWidget {
  final String userId;
  final String name;

  /// Closes the card: a call leaves the voice channel it was opened from.
  final VoidCallback? onCall;

  const MemberCardControls({
    super.key,
    required this.userId,
    required this.name,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final serverId = ServerScope.idOf(context);
    final me = context.select<ServerCubit, String?>(
      (cubit) => cubit.state.meOn(serverId)?.id,
    );
    if (userId == me) return const _OwnControls();
    return _TheirControls(userId: userId, name: name, onCall: onCall);
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
/// it is on, and a call. Moderation is its own section
/// ([MemberCardModeration]).
class _TheirControls extends StatelessWidget {
  final String userId;
  final String name;
  final VoidCallback? onCall;

  const _TheirControls({required this.userId, required this.name, this.onCall});

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
    final isBot = context.select<ServerMembersCubit, bool>(
      (cubit) => cubit.state.byId[userId]?.isBot ?? false,
    );
    final canCall = !isBot && _canCall(context);
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
            // A DM call, as the conversation's header places it. A refusal
            // (requests, blocks) comes back from the server and is said by
            // the call's own notice.
            if (canCall)
              Expanded(
                child: ControlButton(
                  dense: true,
                  icon: Icons.call_rounded,
                  tooltip: 'Call',
                  onTap: () {
                    final calls = context.read<DmCallCubit>();
                    onCall?.call();
                    calls.startCall(
                      serverId: ServerScope.read(context).serverId,
                      peerId: userId,
                      peerName: name,
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The same gate the DM conversation's call button keeps, less what only
  /// an open conversation knows (whether a request was accepted): the server
  /// says that.
  bool _canCall(BuildContext context) {
    final serverId = ServerScope.idOf(context);
    final server = context.select<ServerCubit, ({bool voice, bool connect})>((
      cubit,
    ) {
      final here = cubit.state.serverOn(serverId);
      return (
        voice: here?.livekitUrl != null,
        connect: here?.user?.permissions.can(ServerPermission.connect) ?? false,
      );
    });
    final blocked = context.select<DmCubit, bool>(
      (cubit) => cubit.state.blockedIds.contains(userId),
    );
    return server.voice && server.connect && !blocked;
  }
}
