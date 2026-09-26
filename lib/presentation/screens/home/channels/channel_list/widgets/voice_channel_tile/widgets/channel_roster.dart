import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../data/classes/participant_info.dart';
import '../../../../../../../../data/classes/participant_setting.dart';
import '../../../../../../../../data/classes/voice_drag.dart';
import '../../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../../../common/animated_keyed_column.dart';
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
    // Nobody here: the same column, empty, so it is already standing when
    // the first person arrives and they open into place like everyone after.
    if (participants.isEmpty && presenceUsers.isEmpty && summoned.isEmpty) {
      return const AnimatedKeyedColumn(children: []);
    }
    final canMoveOthers = context.select<ServerCubit, bool>((cubit) {
      final permissions = cubit.state.myPermissions;
      return (permissions?.isServerAdmin ?? false) ||
          (permissions?.isChannelManager ?? false);
    });
    final roster = context.watch<ServerMembersCubit>().state;
    final keys = _RowKeys();

    // Rows touch, as the sidebar's do: a row is [RosterRowMetrics.rowHeight]
    // and so is the step to the next one. Keyed by person, so someone moving
    // from a presence row to a live one as you join isn't an arrival.
    return AnimatedKeyedColumn(
      children: [
        for (final participant in participants)
          _draggable(
            key: keys.forPerson(participant.userId, participant.identity),
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
            key: keys.forPerson(user.userId, user.userId),
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
            SummonedBotRow(
              key: keys.forPerson(bot.id, 'summoned:${bot.id}'),
              botId: bot.id,
              name: bot.name,
              channelId: channelId,
            ),
      ],
    );
  }

  /// Whether this bot is already drawn above, as a participant or from
  /// presence. A summon it answered is not news.
  bool _present(String botId) =>
      participants.any((p) => p.userId == botId) ||
      presenceUsers.any((u) => u.userId == botId);

  Widget _draggable({
    required Key key,
    required String userId,
    required String name,
    required bool enabled,
    bool isLocal = false,
    required Widget child,
  }) => DraggableMember(
    key: key,
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

/// A key per row, by person — and by connection for anyone connected twice,
/// since two devices in one call are two rows and a key may only be used
/// once.
class _RowKeys {
  final _used = <String>{};

  Key forPerson(String userId, String fallback) =>
      ValueKey(_used.add(userId) ? userId : fallback);
}
