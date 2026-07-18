import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../chat/channel_chat_view.dart';
import '../dms/home_dm_view.dart';
import '../participants_grid/participants_grid.dart';

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
        buildWhen: (prev, curr) => prev.homeViewOpen != curr.homeViewOpen,
        builder: (context, appState) {
          if (appState.homeViewOpen) {
            return const HomeDmView();
          }
          return BlocBuilder<ChannelChatCubit, ChannelChatState>(
            buildWhen: (prev, curr) =>
                (prev.channelId == null) != (curr.channelId == null),
            builder: (context, chatState) {
              if (chatState.channelId != null) {
                return const ChannelChatView();
              }
              return const ParticipantsGrid();
            },
          );
        },
      ),
    );
  }
}
