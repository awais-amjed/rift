import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/server_scope.dart';
import '../../invites/show_invite_modal.dart';
import '../../servers/add_server/show_add_server_dialog.dart';
import '../../servers/profile/show_server_profile.dart';
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
    // Selected with the id this build was given, not filtered by a
    // `buildWhen` holding the last one: a builder only takes a new state when
    // its filter lets one through, so a server just joined was looked up in
    // the list from before it existed and the header read "No server
    // selected" over its channels.
    final server = context.select<ServerCubit, Server?>(
      (cubit) => cubit.state.serverOn(serverId),
    );
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
          onShowProfile: () => showServerProfile(context, server: server),
        ),
        JumpField(onTap: () => openQuickSwitcher(context)),
      ],
    );
  }
}

/// Opens the quick switcher. Lives here rather than inside the dialog so both
/// the jump field and the keyboard shortcut open it the same way, with the
/// same cubits passed through.
void openQuickSwitcher(BuildContext context) {
  showCustomDialog(
    context: context,
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
