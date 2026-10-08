import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/apis/channel_access_api.dart';
import '../../../../../data/apis/members_api.dart';
import '../../../../../data/classes/channel.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/repositories/session_repository.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/services/key_holders.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// The people who could hand over a channel's key, and which of them is here.
///
/// Waiting for a key looks like a broken app until you know it is waiting on
/// somebody. This names them: for a private channel, the people in it; for a
/// public one, whoever on the server is online now, since every member holds a
/// public channel's key. If nobody is online that is the most useful thing on
/// the screen — it turns "this is broken" into "ask Kofi to come online".
class KeyHolderList extends StatefulWidget {
  final Channel channel;

  const KeyHolderList({super.key, required this.channel});

  /// Enough to find somebody to ask, without the card becoming a roster.
  static const int _shown = 6;

  @override
  State<KeyHolderList> createState() => _KeyHolderListState();
}

class _KeyHolderListState extends State<KeyHolderList> {
  /// Everyone in a private channel, by id and name. Null until loaded, and
  /// unused for a public channel, whose holders are simply whoever is online.
  Map<String, String>? _seated;

  @override
  void initState() {
    super.initState();
    if (widget.channel.isPrivate) _loadSeated();
  }

  Future<void> _loadSeated() async {
    final session = context.read<SessionRepository>();
    final members = MembersApi(session: session);
    final membership = await ChannelAccessApi(
      session: session,
    ).channelMembers(widget.channel.id);
    final rows = await members.membersByIds(membership.memberIds.toList());
    if (!mounted) return;
    setState(() => _seated = {for (final m in rows) m.id: m.displayName});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final onlineIds = context.select<ChannelPresenceCubit, Set<String>>(
      (c) => c.state.onlineUserIds,
    );
    final roster = context.watch<ServerMembersCubit>().state;
    final me = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServer?.user?.id,
    );

    final Map<String, String> names;
    if (widget.channel.isPrivate) {
      final seated = _seated;
      if (seated == null) return const SizedBox.shrink();
      names = seated;
    } else {
      names = {
        for (final id in onlineIds)
          if (roster.byId[id] case final member? when !member.isBot)
            id: member.displayName,
      };
    }
    final holders = orderKeyHolders(names: names, onlineIds: onlineIds, me: me);
    final anyOnline = holders.any((h) => h.online);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(
            'WHO CAN HAND OVER THE KEY',
            style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
          ),
          if (!anyOnline)
            Text(
              holders.isEmpty
                  ? 'Nobody who holds this key is online right now.'
                  : 'None of them is online right now — the key arrives when '
                        'one of them is.',
              style: AppText.meta.copyWith(color: theme.textSecondary),
            ),
          for (final holder in holders.take(KeyHolderList._shown))
            Row(
              spacing: 9,
              children: [
                SquircleAvatar(name: holder.name, seed: holder.id, size: 22),
                Expanded(
                  child: Text(
                    holder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowQuiet.copyWith(color: theme.textPrimary),
                  ),
                ),
                if (holder.online) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: CustomColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    'Online',
                    style: AppText.meta.copyWith(
                      color: CustomColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else
                  Text(
                    'Offline',
                    style: AppText.meta.copyWith(color: theme.textTertiary),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
