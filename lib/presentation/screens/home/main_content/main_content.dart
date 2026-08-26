import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_panel.dart';
import '../../../responsive/shell_scope.dart';
import '../chat/channel_chat_view.dart';
import 'home_view.dart';
import '../chat/widgets/header_pane_buttons.dart';
import '../dms/central_dm_view.dart';
import '../dms/server_dm_view.dart';
import '../members_sidebar/members_sidebar.dart';
import '../members_sidebar/widgets/members_sidebar_tab.dart';
import 'widgets/banned_notice.dart';
import '../participants_grid/participants_grid.dart';

/// The centre pane's panel. Content panels sit one rung above the canvas on
/// their own surface, which is what separates them from the chrome panels
/// either side.
class _ContentPanel extends StatelessWidget {
  final Widget child;

  const _ContentPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      buildWhen: (a, b) => a.bgContent != b.bgContent,
      builder: (context, themeState) =>
          AppPanel(color: themeState.bgContent, child: child),
    );
  }
}

/// The home screen's center pane: the Home (DMs) surface when open, else
/// text-channel chat when one is open, otherwise the voice/video area.
///
/// Owns the voice connect/disconnect listener so it stays mounted regardless
/// of which pane is showing — you can read chat or DMs while remaining in a
/// voice call.
class MainContent extends StatelessWidget {
  const MainContent({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.selectedChannelId != curr.selectedChannelId,
      listener: (context, appState) {
        final livekitCubit = context.read<LiveKitCubit>();
        final serverState = context.read<ServerCubit>().state;
        final server = serverState.selectedServer;

        if (appState.selectedChannelId == null) {
          livekitCubit.disconnect();
          return;
        }

        if (server == null) return;
        if (server.user == null) return;
        if (server.livekitUrl == null) return;

        livekitCubit.connectToChannel(
          channelId: appState.selectedChannelId!,
          micEnabled: appState.audioEnabled,
          cameraEnabled: appState.videoEnabled,
        );
      },
      child: BlocBuilder<AppCubit, AppState>(
        // The channel matters here as well as the surface: on a phone the
        // pane swaps between the server's list and a live call, and joining a
        // call changes only the channel.
        buildWhen: (prev, curr) =>
            prev.surface != curr.surface ||
            prev.selectedChannelId != curr.selectedChannelId,
        builder: (context, appState) {
          // Neither DM surface is channel-scoped, so the server member list
          // has nothing to say on either.
          // On a phone the pane shows where you *are* until you open
          // something in it — see [HomeView]. A conversation or a channel
          // takes over the moment there is one.
          final compact = context.layoutMode.isCompact;

          // A ban empties every read on the server, so without this the pane
          // would show an empty channel that never loads. Central DMs are a
          // different tier and keep working, which is worth leaving reachable
          // — it is how you'd reach whoever banned you.
          final bannedFrom = context.select<ServerCubit, String?>((cubit) {
            final server = cubit.state.selectedServer;
            return (server?.user?.isBanned ?? false) ? server!.name : null;
          });
          if (bannedFrom != null &&
              appState.surface != HomeSurface.centralDms) {
            return _ContentPanel(
              child: _HeaderlessMenu(
                child: BannedNotice(serverName: bannedFrom),
              ),
            );
          }

          if (appState.surface.isDms) {
            // Server DMs keep their own list inside the pane, so on a phone
            // they are already somewhere you can stand and [HomeView] would
            // put the server's channels where the conversations should be.
            // Central's list is in the sidebar, so its pane has nothing to
            // rest on and HomeView is what it rests on.
            if (appState.surface == HomeSurface.serverDms) {
              return const _ContentPanel(
                child: _WithMenuWhenHeaderless(
                  hasOwnHeader: _ServerDmHasHeader(),
                  child: ServerDmView(),
                ),
              );
            }
            // Friends counts as somewhere to stand: on a phone the pane with
            // nothing open is the conversation list, so without this the
            // friends page would be unreachable there.
            final conversationOpen = context.select<CentralDmCubit, bool>(
              (c) => c.state.openPeerId != null || c.state.friendsOpen,
            );
            if (compact && !conversationOpen) {
              return const _ContentPanel(child: HomeView());
            }
            return const _ContentPanel(
              child: _WithMenuWhenHeaderless(
                hasOwnHeader: _CentralDmOpen(),
                child: CentralDmView(),
              ),
            );
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
                            (prev.channelId == null) !=
                            (curr.channelId == null),
                        builder: (context, chatState) {
                          if (chatState.channelId != null) {
                            return const ChannelChatView();
                          }
                          // The voice grid is for a call in progress. Until
                          // there is one, a phone shows the server rather
                          // than a sentence about the sidebar it cannot see.
                          if (compact && appState.selectedChannelId == null) {
                            return const HomeView();
                          }
                          // The voice area has no header of its own, so on a
                          // phone there would be nothing anywhere on screen
                          // that opens the channel list.
                          return const _HeaderlessMenu(
                            child: ParticipantsGrid(),
                          );
                        },
                      ),
                    ),
                  ),
                  // The gutter beside it belongs to the member list now, so it
                  // goes away when the list does.
                  if (membersDocked) MembersSidebar(open: shell.membersOpen),
                ],
              ),
              // Sits over the content's right edge, mirroring the left
              // sidebar's tab. Above the Row so it isn't clipped by the panel
              // that just slid out from under it. On a phone the chat header's
              // own button takes over, within reach of a thumb.
              if (!context.layoutMode.isCompact)
                const Positioned(top: 12, right: 0, child: MembersSidebarTab()),
            ],
          );
        },
      ),
    );
  }
}

/// Puts the drawer button over content that has no header to carry it.
///
/// Three of the content pane's states are bare — the voice area, and each DM
/// surface before a conversation is opened. On a phone the sidebar is a
/// drawer, so a state with no way to open it is a dead end: the resting
/// central-DM screen even says "find someone in the panel on the left", with
/// no panel and no way to summon one. Two of those three are what you see
/// first, before anything has been picked.
///
/// Renders nothing but its child at wider sizes, where the sidebar is docked
/// and [HeaderSidebarButton] returns an empty box anyway.
class _HeaderlessMenu extends StatelessWidget {
  final Widget child;

  const _HeaderlessMenu({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const Positioned(top: 10, left: 10, child: HeaderSidebarButton()),
      ],
    );
  }
}

/// [_HeaderlessMenu], but only while [hasOwnHeader] says the surface is in a
/// state that doesn't already have one — an open conversation brings a
/// [DmChatHeader] with the button already in it, and two would be one too many.
class _WithMenuWhenHeaderless extends StatelessWidget {
  final Widget hasOwnHeader;
  final Widget child;

  const _WithMenuWhenHeaderless({
    required this.hasOwnHeader,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(top: 10, left: 10, child: hasOwnHeader),
    ],
  );
}

/// The drawer button, unless a central conversation is open.
class _CentralDmOpen extends StatelessWidget {
  const _CentralDmOpen();

  @override
  Widget build(BuildContext context) {
    final open = context.select<CentralDmCubit, bool>(
      (cubit) => cubit.state.openPeerId != null,
    );
    return open ? const SizedBox.shrink() : const HeaderSidebarButton();
  }
}

/// The drawer button, unless the server-DM surface already has a header.
///
/// On a phone it always does: an open conversation brings a [DmChatHeader] and
/// the resting state is the conversation list, whose own header carries the
/// button. Only the wide layout's empty panel is bare, and there the sidebar is
/// docked and [HeaderSidebarButton] is empty anyway — so this is nothing on
/// every path but the one it exists for.
class _ServerDmHasHeader extends StatelessWidget {
  const _ServerDmHasHeader();

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) return const SizedBox.shrink();
    final open = context.select<DmCubit, bool>(
      (cubit) => cubit.state.openPeerId != null,
    );
    return open ? const SizedBox.shrink() : const HeaderSidebarButton();
  }
}
