import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../logic/cubits/server_reach/server_reach_cubit.dart';
import '../../../common/app_sheet.dart';
import '../../../common/loading_dots.dart';
import '../../../common/server_scope.dart';
import '../../../common/sheet_handle.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../members_sidebar/widgets/members_sidebar_list.dart';
import 'mobile_shell_scope.dart';

/// The member list on a phone: a sheet over the chat rather than a second
/// drawer.
///
/// A drawer from the right edge would compete with the back gesture for the
/// same strip of screen. A sheet leaves the conversation visible above it and
/// goes away with a swipe down — it is something you glance at, not somewhere
/// you go, so it adds no level to back.
///
/// The sheet is a route of its own, above the shell, so it carries the
/// shell's navigation with it: a Watch from a member row asked for the
/// shell's call page and, finding none, took the desktop's path to a channel
/// list. And it goes once something is opened from it, since what was opened
/// is underneath.
Future<void> showMembersSheet(BuildContext context) {
  final shell = MobileShellScope.maybeOf(context);
  return showAppSheet<void>(
    context,
    _ClosesOnNavigation(
      child: Builder(
        builder: (sheetContext) {
          const sheet = FractionallySizedBox(
            heightFactor: 0.8,
            child: _MembersSheet(),
          );
          if (shell == null) return sheet;
          return MobileShellScope(
            openCall: () {
              _close(sheetContext);
              shell.openCall();
            },
            callOnTop: false,
            child: sheet,
          );
        },
      ),
    ),
  );
}

/// Takes the sheet's own route away, whatever is above it: a profile opened
/// from a row may still be on top.
void _close(BuildContext sheetContext) {
  final route = ModalRoute.of(sheetContext);
  if (route == null || !route.isActive) return;
  Navigator.of(sheetContext).removeRoute(route);
}

/// Closes the sheet when a channel, a call or a conversation opens from it.
class _ClosesOnNavigation extends StatelessWidget {
  final Widget child;

  const _ClosesOnNavigation({required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AppCubit, AppState>(
          listenWhen: (prev, curr) =>
              prev.selectedChannelId != curr.selectedChannelId ||
              prev.surface != curr.surface,
          listener: (context, _) => _close(context),
        ),
        BlocListener<ChannelChatCubit, ChannelChatState>(
          listenWhen: (prev, curr) => prev.channelId != curr.channelId,
          listener: (context, _) => _close(context),
        ),
        BlocListener<DmCubit, DmState>(
          listenWhen: (prev, curr) => prev.openPeerId != curr.openPeerId,
          listener: (context, _) => _close(context),
        ),
      ],
      child: child,
    );
  }
}

class _MembersSheet extends StatelessWidget {
  const _MembersSheet();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    // Selected, as the desktop list is: who is speaking lands in the app
    // state several times a second in a call, presence carries every voice
    // channel's people, and the list draws none of that. Only the people's
    // own settings come from the app state.
    context.select((AppCubit c) => c.state.participantSettings);
    final appState = context.read<AppCubit>().state;
    final serverId = ServerScope.idOf(context);
    final myId = context.select((ServerCubit c) => c.state.meOn(serverId)?.id);
    final onlineIds = context.select(
      (ChannelPresenceCubit c) => c.state.onlineUserIds,
    );
    final onlineKnown = context.select(
      (ChannelPresenceCubit c) => c.state.onlineKnown,
    );
    final roster = context.watch<ServerMembersCubit>().state;
    // People only, as in the desktop header: the bots carry their own count
    // under their own heading.
    final count = roster.loaded ? roster.peopleCount : null;

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(margin: EdgeInsets.only(top: 8)),
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
                    onlineIds: onlineIds,
                    onlineKnown: onlineKnown,
                    reachable: context.select(
                      (ServerReachCubit c) => c.state.unreachableName == null,
                    ),
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
