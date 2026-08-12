import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../servers/widgets/no_server_button.dart';
import '../../servers/add_server/add_server_dialog.dart';
import '../../servers/server_settings/server_settings_dialog.dart';
import '../quick_switcher/quick_switcher_dialog.dart';
import 'jump_field.dart';
import 'server_header.dart';

/// The top of the sidebar column: which server you are in, and the way to get
/// somewhere else inside it.
class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      buildWhen: (a, b) => a.selectedServer != b.selectedServer,
      builder: (context, serverState) {
        final server = serverState.selectedServer;
        if (server == null) {
          return NoServerButton(onTap: () => _openAddServerDialog(context));
        }

        final isAdmin = server.user?.permissions.isServerAdmin ?? false;
        return Column(
          children: [
            ServerHeader(
              server: server,
              onOpenSettings: isAdmin
                  ? () => _openServerSettings(context)
                  : null,
            ),
            JumpField(onTap: () => openQuickSwitcher(context)),
          ],
        );
      },
    );
  }

  /// Admin-only settings for the selected server: connection, limits, and its
  /// listing in the central directory.
  void _openServerSettings(BuildContext context) {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<ThemeCubit>()),
          // The discovery column lives on central rather than on the server.
          BlocProvider.value(value: context.read<PublicServersCubit>()),
          BlocProvider.value(value: context.read<ServerMembersCubit>()),
          BlocProvider.value(value: context.read<SupabaseBackupCubit>()),
        ],
        child: const ServerSettingsDialog(),
      ),
    );
  }

  /// Joining or creating a server.
  void _openAddServerDialog(BuildContext context) {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<AppCubit>()),
        ],
        child: const AddServerDialog(),
      ),
    );
  }
}

/// Opens the quick switcher. Lives here rather than inside the dialog so both
/// the jump field and the keyboard shortcut open it the same way, with the
/// same cubits passed through.
void openQuickSwitcher(BuildContext context) {
  showCustomDialog(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<ServerCubit>()),
        BlocProvider.value(value: context.read<AppCubit>()),
        BlocProvider.value(value: context.read<ChannelChatCubit>()),
        BlocProvider.value(value: context.read<ThemeCubit>()),
      ],
      child: const QuickSwitcherDialog(),
    ),
  );
}
