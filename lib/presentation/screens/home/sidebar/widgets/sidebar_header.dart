import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../servers/add_server/add_server_dialog.dart';
import '../../servers/manage/server_manage_dialog.dart';
import '../../servers/manage/server_manage_tab.dart';
import '../../servers/widgets/no_server_button.dart';
import '../quick_switcher/quick_switcher_dialog.dart';
import 'jump_field.dart';
import 'server_header.dart';

/// The top of the sidebar column: which server you are in, and the way to get
/// somewhere else inside it.
class SidebarHeader extends StatelessWidget {
  /// Passed through to [ServerHeader] — see its doc.
  final bool showHideButton;

  const SidebarHeader({super.key, this.showHideButton = true});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      buildWhen: (a, b) => a.selectedServer != b.selectedServer,
      builder: (context, serverState) {
        final server = serverState.selectedServer;
        if (server == null) {
          return NoServerButton(onTap: () => _openAddServerDialog(context));
        }

        // The gear opens for anybody with a page in there, not only an
        // administrator — same rule as the rail's menu, and for the same
        // reason: the dialog decides what its pages need.
        final canManage = ServerManageTabs.visible(
          server.user?.permissions,
        ).isNotEmpty;
        return Column(
          children: [
            ServerHeader(
              server: server,
              showHideButton: showHideButton,
              onOpenSettings: canManage
                  ? () => _openServerSettings(context, server)
                  : null,
            ),
            JumpField(onTap: () => openQuickSwitcher(context)),
          ],
        );
      },
    );
  }

  /// Everything about running [server] — here, always the one this header is
  /// showing — opened on its first page, which for an administrator is the
  /// overview and for anybody else is whatever they actually hold.
  void _openServerSettings(BuildContext context, Server server) {
    showServerManageDialog(context, server: server);
  }

  /// Joining or creating a server.
  void _openAddServerDialog(BuildContext context) {
    showCustomDialog(
      context: context,
      build: (_) => MultiBlocProvider(
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
    // A picker, not a form: nothing typed into it is worth keeping, so a
    // click anywhere else should close it the way Escape does.
    barrierDismissible: true,
    build: (_) => MultiBlocProvider(
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
