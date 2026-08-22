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
import '../chat/widgets/header_pane_buttons.dart';
import '../dms/central_dm_view.dart';
import '../dms/server_dm_view.dart';
import '../members_sidebar/members_sidebar.dart';
import '../members_sidebar/widgets/members_sidebar_tab.dart';
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
        buildWhen: (prev, curr) => prev.surface != curr.surface,
        builder: (context, appState) {
          // Neither DM surface is channel-scoped, so the server member list
          // has nothing to say on either.
          if (appState.surface.isDms) {
            return _ContentPanel(
              child: appState.surface == HomeSurface.centralDms
                  ? const _WithMenuWhenHeaderless(
                      hasOwnHeader: _CentralDmOpen(),
                      child: CentralDmView(),
                    )
                  : const _WithMenuWhenHeaderless(
                      hasOwnHeader: _ServerDmOpen(),
                      child: ServerDmView(),
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
                          // The voice area has no header of its own, so on a
                          // phone there would be nothing anywhere on screen
                          // that opens the channel list — and with no channel
                          // picked yet, this is the first thing you see.
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

/// The drawer button, unless a server conversation is open.
class _ServerDmOpen extends StatelessWidget {
  const _ServerDmOpen();

  @override
  Widget build(BuildContext context) {
    final open = context.select<DmCubit, bool>(
      (cubit) => cubit.state.openPeerId != null,
    );
    return open ? const SizedBox.shrink() : const HeaderSidebarButton();
  }
}
