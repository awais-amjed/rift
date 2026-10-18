import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/server_scope.dart';
import '../../invites/show_invite_modal.dart';
import '../../servers/add_server/show_add_server_dialog.dart';
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
    final serverId = ServerScope.idOf(context);
    return BlocBuilder<ServerCubit, ServerState>(
      buildWhen: (a, b) => a.serverOn(serverId) != b.serverOn(serverId),
      builder: (context, serverState) {
        final server = serverState.serverOn(serverId);
        if (server == null) {
          return NoServerButton(onTap: () => showAddServerDialog(context));
        }

        return Column(
          children: [
            ServerHeader(
              server: server,
              showHideButton: showHideButton,
              onInvite: (server.user?.permissions.canCreateTokens ?? false)
                  ? () => showInviteModal(context, server: server)
                  : null,
            ),
            JumpField(onTap: () => openQuickSwitcher(context)),
          ],
        );
      },
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
