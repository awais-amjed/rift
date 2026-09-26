import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../data/classes/participant_info.dart';
import '../../../../../../../../data/classes/participant_setting.dart';
import '../../../../../../../../data/classes/voice_drag.dart';
import '../../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../sidebar/widgets/draggable_member.dart';
import '../../../../../sidebar/widgets/participant_context_menu.dart';
import '../../../../../sidebar/widgets/participant_list_item.dart';
import 'presence_member_row.dart';
import 'summoned_bot_row.dart';

/// The people inside one voice channel, from both of the places we know about
/// them: LiveKit when it's the call we're in, Realtime presence when it isn't.
///
/// Every row can be picked up and dropped on another channel — staff can drag
/// anyone, everyone can drag themselves, which is a longer way of clicking the
/// channel you want to be in. Names always come from the roster rather than
/// either source's own copy, so a rename shows up mid-call.
class ChannelRoster extends StatelessWidget {
  final String channelId;

  /// Connected participants — full LiveKit state (speaking, mute, moderation).
  final List<ParticipantInfo> participants;

  /// Bots summoned into this channel, arrived or not.
  final List<SummonedBot> summoned;

  /// Members of this channel seen only through presence, with no live state.
  final List<PresenceUser> presenceUsers;

  final Map<String, ParticipantSetting> settings;
  const ChannelRoster({
    super.key,
    required this.channelId,
    required this.participants,
    required this.presenceUsers,
    this.summoned = const [],
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final canMoveOthers = context.select<ServerCubit, bool>((cubit) {
      final permissions = cubit.state.myPermissions;
      return (permissions?.isServerAdmin ?? false) ||
          (permissions?.isChannelManager ?? false);
    });
    final roster = context.watch<ServerMembersCubit>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // Touching, as the sidebar's rows do: a row is [RosterRowMetrics.rowHeight]
      // and so is the step to the next one.
      children: [
        for (final participant in participants)
          _draggable(
            userId: participant.userId,
            name: roster.nameFor(participant.userId, participant.name),
            isLocal: participant.isLocal,
            enabled: canMoveOthers || participant.isLocal,
            child: ParticipantListItem(
              participant: participant,
              setting: settings[participant.userId],
              contextMenu: ParticipantContextMenu(
                identity: participant.identity,
                name: roster.nameFor(participant.userId, participant.name),
                isLocal: participant.isLocal,
              ),
            ),
          ),
        for (final user in presenceUsers)
          _draggable(
            userId: user.userId,
            name: roster.nameFor(user.userId, user.displayName),
            enabled: canMoveOthers,
            child: PresenceMemberRow(
              user: user,

              setting: settings[user.userId],
            ),
          ),
        // Bots that were called in and have not turned up. The two lists above
        // are drawn from who is connected, and a bot that is down leaves
        // nothing there — see [SummonedBotRow]. Not draggable: there is no
        // connection to move.
        for (final bot in summoned)
          if (!_present(bot.id))
            SummonedBotRow(botId: bot.id, name: bot.name, channelId: channelId),
      ],
    );
  }

  /// Whether this bot is already drawn above, as a participant or from
  /// presence. A summon it answered is not news.
  bool _present(String botId) =>
      participants.any((p) => p.userId == botId) ||
      presenceUsers.any((u) => u.userId == botId);

  Widget _draggable({
    required String userId,
    required String name,
    required bool enabled,
    bool isLocal = false,
    required Widget child,
  }) => DraggableMember(
    enabled: enabled,
    member: VoiceDrag(
      userId: userId,
      name: name,
      fromChannelId: channelId,
      isLocal: isLocal,
    ),
    child: child,
  );
}
