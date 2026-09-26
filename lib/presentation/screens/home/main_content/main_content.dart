import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/app_panel.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';
import '../chat/channel_chat_view.dart';
import '../dms/central_dm_view.dart';
import '../dms/server_dm_view.dart';
import '../members_sidebar/members_sidebar.dart';
import '../participants_grid/participants_grid.dart';
import 'widgets/banned_notice.dart';

/// The centre pane's panel. Content panels sit one rung above the canvas on
/// their own surface, which is what separates them from the chrome panels
/// either side.
class _ContentPanel extends StatelessWidget {
  final Widget child;

  const _ContentPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final immersive = ShellScope.of(context).immersive;
    final themeState = context.theme;
    // Corners and border melt away with the gutter around them, on the same
    // clock — see `ShellScope.immersive`.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: immersive ? 1 : 0),
      duration: AppMotion.enter,
      curve: AppMotion.panel,
      child: child,
      builder: (context, bleed, child) =>
          AppPanel(color: themeState.bgContent, bleed: bleed, child: child!),
    );
  }
}

/// The desktop's centre pane: the DM surface when one is open, else
/// text-channel chat when one is open, otherwise the voice area.
///
/// A phone never builds this — its shell pushes each of these as a page of its
/// own (see `MobileShell`).
class MainContent extends StatelessWidget {
  const MainContent({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (prev, curr) => prev.surface != curr.surface,
      builder: (context, appState) {
        // A ban empties every read on the server, so without this the pane
        // would show an empty channel that never loads. Central DMs are a
        // different tier and keep working, which is worth leaving reachable
        // — it is how you'd reach whoever banned you.
        final bannedFrom = context.select<ServerCubit, String?>((cubit) {
          final server = cubit.state.selectedServer;
          return (server?.user?.isBanned ?? false) ? server!.name : null;
        });
        if (bannedFrom != null && appState.surface != HomeSurface.centralDms) {
          return _ContentPanel(child: BannedNotice(serverName: bannedFrom));
        }

        // Neither DM surface is channel-scoped, so the server member list
        // has nothing to say on either.
        switch (appState.surface) {
          case HomeSurface.serverDms:
            return const _ContentPanel(child: ServerDmView());
          case HomeSurface.centralDms:
            return const _ContentPanel(child: CentralDmView());
          case HomeSurface.server:
            break;
        }

        // Overlaid, the member list is mounted by the shell so it can float
        // over the sidebar too; here it would be trapped inside the content
        // pane. Docked, it belongs beside the chat, which is here.
        final membersDocked = !context.layoutMode.membersIsOverlay;
        final shell = ShellScope.of(context);

        return Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ContentPanel(
                    child: BlocBuilder<ChannelChatCubit, ChannelChatState>(
                      buildWhen: (prev, curr) =>
                          (prev.channelId == null) != (curr.channelId == null),
                      builder: (context, chatState) =>
                          chatState.channelId != null
                          ? const ChannelChatView()
                          : const ParticipantsGrid(),
                    ),
                  ),
                ),
                // The gutter beside it belongs to the member list now, so it
                // goes away when the list does.
                if (membersDocked) MembersSidebar(open: shell.membersOpen),
              ],
            ),
          ],
        );
      },
    );
  }
}
