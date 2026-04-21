import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../logic/cubits/server/server_cubit.dart';
import 'add_server_button.dart';
import 'empty_server_list.dart';
import 'server_list_item.dart';

/// Widget displaying the list of servers or an empty state.
class ServerListView extends StatelessWidget {
  final VoidCallback onAddServer;
  final VoidCallback onClose;

  const ServerListView({
    super.key,
    required this.onAddServer,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      builder: (context, state) {
        if (state.servers.isEmpty) {
          return EmptyServerList(onAddServer: onAddServer);
        }

        return Column(
          children: [
            ...state.servers.map(
              (server) => ServerListItem(
                server: server,
                isSelected: server.id == state.selectedServer?.id,
                onTap: () {
                  context.read<ServerCubit>().selectServer(server);
                  onClose();
                },
                onDelete: () {
                  context.read<ServerCubit>().removeServer(server.id);
                },
              ),
            ),
            const SizedBox(height: 12),
            AddServerButton(onTap: onAddServer),
          ],
        );
      },
    );
  }
}
