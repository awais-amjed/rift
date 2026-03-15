import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/app_modal.dart';
import '../../channels/create_channel_dialog.dart';
import '../../invites/invite_modal.dart';
import '../../servers/server_action_bar.dart';

/// Action bar with invite and create channel buttons (if user has permissions).
class SidebarActions extends StatelessWidget {
  const SidebarActions({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      builder: (context, serverState) {
        final server = serverState.selectedServer;
        final permissions = server?.user?.permissions;
        if (permissions == null) return const SizedBox.shrink();

        final showAny =
            permissions.canCreateTokens || permissions.isChannelManager;
        if (!showAny) return const SizedBox.shrink();

        return ServerActionBar(
          permissions: permissions,
          onInvite: () => showCustomDialog(
            context: context,
            builder: (_) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: context.read<ServerCubit>()),
                BlocProvider.value(value: context.read<AppCubit>()),
              ],
              child: const InviteModal(),
            ),
          ),
          onCreateChannel: () => showCustomDialog(
            context: context,
            builder: (_) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: context.read<ServerCubit>()),
                BlocProvider.value(value: context.read<AppCubit>()),
              ],
              child: const CreateChannelDialog(),
            ),
          ),
        );
      },
    );
  }
}
