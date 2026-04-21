import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../channels/channel_list/channel_list.dart';

/// Wrapper for the channel list that handles channel selection.
class SidebarChannelList extends StatelessWidget {
  const SidebarChannelList({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      builder: (context, serverState) {
        final channels = serverState.selectedServer?.channels ?? [];

        return BlocBuilder<AppCubit, AppState>(
          buildWhen: (prev, curr) =>
              prev.selectedChannelId != curr.selectedChannelId,
          builder: (context, appState) {
            return ChannelList(
              channels: channels,
              selectedChannelId: appState.selectedChannelId,
              onChannelSelect: (id) =>
                  context.read<AppCubit>().setSelectedChannelId(id),
            );
          },
        );
      },
    );
  }
}
