import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/server_reach/server_reach_cubit.dart';
import '../../../../../logic/services/member_roster.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// A server's second line: that it is encrypted, and who is here.
///
/// Presence is followed for the selected server only, which is the one this
/// header names, so the count is live and costs nothing to read.
class SwitcherServerLine extends StatelessWidget {
  final String serverId;

  const SwitcherServerLine({super.key, required this.serverId});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final onlineIds = context.select<ChannelPresenceCubit, Set<String>?>(
      (c) => c.state.onlineKnown ? c.state.onlineUserIds : null,
    );
    // The people the member list puts under Online, not the presence set,
    // which holds the bots and anybody not named yet as well.
    final online = context.select<ServerMembersCubit, int?>(
      (c) => onlineIds == null || !c.state.loaded
          ? null
          : MemberRoster.onlineCount(
              known: c.state.known.values,
              people: c.state.people.members,
              onlineIds: onlineIds,
            ),
    );
    final reachable = context.select<ServerReachCubit, bool>(
      (c) => c.state.unreachableName == null,
    );
    return Row(
      spacing: 5,
      children: [
        Icon(
          Icons.lock_outline,
          size: K.iconTiny,
          color: context.theme.statusInk(CustomColors.success),
        ),
        // Not "0 online" while presence or the roster has yet to answer.
        if (online == null) ...[
          // Out of reach, there is no count to wait for.
          if (reachable) LoadingDots(color: theme.textQuaternary, dotSize: 3),
        ] else
          Text(
            '$online online',
            style: AppText.label.copyWith(color: theme.textTertiary),
          ),
      ],
    );
  }
}
