import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/apis/voice_bots_api.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../data/repositories/session_repository.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../theme/theme_context.dart';

/// Sending a summoned bot away.
///
/// Only for a bot, and only from a call it is actually in — a summon is per
/// channel (`bot_voice_summons`), so "send away" needs to name one and the one it
/// names is the room you are looking at.
///
/// **Not behind `MANAGE_BOTS`.** Dismissing needs no more than being able to
/// see the channel: anybody in a call may ask the music bot to stop, and
/// requiring the person who summoned it — who may well have left — is how a bot
/// ends up playing to an empty room. It is offered to holders of `SUMMON_BOTS`
/// because that is the same people, minus a server that deliberately took the
/// bit away.
class ParticipantBotSection extends StatelessWidget {
  /// The bot's user id.
  final String targetUserId;

  /// The voice channel to send it away from, or null when the target is not in
  /// one we know about — in which case there is nothing to offer.
  final String? voiceChannelId;

  final String name;

  const ParticipantBotSection({
    super.key,
    required this.targetUserId,
    required this.voiceChannelId,
    required this.name,
  });

  Future<void> _dismiss(BuildContext context) async {
    final dismissMenu = ContextMenuScope.of(context);
    final api = VoiceBotsApi(session: context.read<SessionRepository>());
    final voiceBots = context.read<VoiceListenersCubit>();
    final channelId = voiceChannelId;
    if (channelId == null) return;

    dismissMenu?.call();
    final result = await api.setBotVoiceSummon(
      channelId: channelId,
      botId: targetUserId,
      summon: false,
    );
    if (result.success) {
      // The row is what the sidebar draws a summoned-but-absent bot from, so
      // re-read it or the thing just dismissed stays on screen.
      await voiceBots.refresh();
      HelperMethods.showToast(
        title: 'Sent away',
        description: '$name has left the call.',
      );
      return;
    }
    HelperMethods.showError(error: result.error ?? 'Could not send it away');
  }

  @override
  Widget build(BuildContext context) {
    if (voiceChannelId == null) return const SizedBox.shrink();

    final isBot =
        context.watch<ServerMembersCubit>().state.byId[targetUserId]?.isBot ??
        false;
    if (!isBot) return const SizedBox.shrink();

    final permissions = context
        .watch<ServerCubit>()
        .state
        .selectedServer
        ?.user
        ?.permissions;
    if (!(permissions?.can(ServerPermission.summonBots) ?? false)) {
      return const SizedBox.shrink();
    }

    final themeState = context.theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 9, color: themeState.borderPrimary),
        ContextMenuItem(
          icon: Icons.logout_rounded,
          label: 'Send away',
          onTap: () => _dismiss(context),
        ),
      ],
    );
  }
}
