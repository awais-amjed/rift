import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../common/loading_dots.dart';
import '../../../common/popover_surface.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../members_sidebar/widgets/members_sidebar_list.dart';

/// The member list on a phone: a sheet over the chat rather than a second
/// drawer.
///
/// A drawer from the right edge would compete with the back gesture for the
/// same strip of screen. A sheet leaves the conversation visible above it and
/// goes away with a swipe down — it is something you glance at, not somewhere
/// you go, so it adds no level to back.
Future<void> showMembersSheet(BuildContext context) {
  final theme = context.theme;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: theme.bgSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PopoverSurface.radius),
      ),
    ),
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 0.8, child: _MembersSheet()),
  );
}

class _MembersSheet extends StatelessWidget {
  const _MembersSheet();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final appState = context.watch<AppCubit>().state;
    final myId = context.watch<ServerCubit>().state.selectedServer?.user?.id;
    final presence = context.watch<ChannelPresenceCubit>().state;
    final roster = context.watch<ServerMembersCubit>().state;
    final count = roster.loaded
        ? roster.peopleCount + roster.bots.length
        : null;

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: theme.borderElevated,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: 8,
              children: [
                Text(
                  'Members',
                  style: AppText.dialogTitle.copyWith(color: theme.textPrimary),
                ),
                if (count != null)
                  Text(
                    '$count',
                    style: AppText.figure.copyWith(color: theme.textTertiary),
                  ),
              ],
            ),
          ),
          Expanded(
            child: !roster.loaded
                ? Center(
                    child: LoadingDots(
                      color: context.theme.accentBright,
                      dotSize: 4,
                    ),
                  )
                : MembersSidebarList(
                    appState: appState,
                    roster: roster,
                    onlineIds: presence.onlineUserIds,
                    myId: myId,
                    onLoadMore: () => unawaited(
                      context.read<ServerMembersCubit>().loadMorePeople(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
