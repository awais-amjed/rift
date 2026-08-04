import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_panel.dart';
import '../chat/channel_chat_view.dart';
import '../dms/central_dm_view.dart';
import '../dms/server_dm_view.dart';
import '../members_sidebar/members_sidebar.dart';
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
                  ? const CentralDmView()
                  : const ServerDmView(),
            );
          }
          return Row(
            children: [
              Expanded(
                child: _ContentPanel(
                  child: BlocBuilder<ChannelChatCubit, ChannelChatState>(
                    buildWhen: (prev, curr) =>
                        (prev.channelId == null) != (curr.channelId == null),
                    builder: (context, chatState) {
                      if (chatState.channelId != null) {
                        return const ChannelChatView();
                      }
                      return const ParticipantsGrid();
                    },
                  ),
                ),
              ),
              const SizedBox(width: K.panelGutter),
              const MembersSidebar(),
            ],
          );
        },
      ),
    );
  }
}
