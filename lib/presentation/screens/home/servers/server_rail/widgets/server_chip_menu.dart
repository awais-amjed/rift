import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../invites/invite_modal.dart';
import '../../server_settings/server_settings_dialog.dart';

/// Right-click menu on a rail chip.
///
/// This is where the actions that used to live in the server-selector list
/// went when the rail replaced it — invite, settings, mark read, and leaving.
/// They belong on the server they act on rather than in a dialog listing all
/// of them.
class ServerChipMenu extends StatelessWidget {
  final Server server;

  const ServerChipMenu({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    final permissions = server.user?.permissions;
    final hasUnread = context.select<ServerNotificationsCubit, bool>(
      (c) => c.state.unreadForServer(server.id) > 0,
    );

    return ContextMenuPanel(
      heading: 'Server',
      subheading: server.name,
      children: [
        if (hasUnread)
          ContextMenuItem(
            icon: Icons.mark_chat_read_outlined,
            label: 'Mark as read',
            onTap: () {
              ContextMenuScope.of(context)?.call();
              context.read<ServerNotificationsCubit>().markServerRead(
                server.id,
              );
            },
          ),
        if (permissions?.canCreateTokens ?? false)
          ContextMenuItem(
            icon: Icons.person_add_outlined,
            label: 'Invite people',
            onTap: () => _open(
              context,
              (ctx) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: ctx.read<ServerCubit>()),
                  BlocProvider.value(value: ctx.read<AppCubit>()),
                ],
                child: const InviteModal(),
              ),
            ),
          ),
        if (permissions?.isServerAdmin ?? false)
          ContextMenuItem(
            icon: Icons.settings_outlined,
            label: 'Server settings',
            onTap: () => _open(
              context,
              (ctx) => BlocProvider.value(
                value: ctx.read<ServerCubit>(),
                child: const ServerSettingsDialog(),
              ),
            ),
          ),
        ContextMenuItem(
          icon: Icons.logout_rounded,
          label: 'Leave server',
          isDangerous: true,
          onTap: () => _leave(context),
        ),
      ],
    );
  }

  /// Menus are overlay entries, not routes, so anything that opens a dialog
  /// has to dismiss the menu itself first — and read its cubits before the
  /// menu's own context is torn down.
  void _open(BuildContext context, Widget Function(BuildContext) builder) {
    final dismiss = ContextMenuScope.of(context);
    final host = context;
    dismiss?.call();
    showCustomDialog(context: host, builder: (_) => builder(host));
  }

  Future<void> _leave(BuildContext context) async {
    final dismiss = ContextMenuScope.of(context);
    final serverCubit = context.read<ServerCubit>();
    final host = context;
    dismiss?.call();

    final confirmed = await showConfirmDialog(
      context: host,
      title: 'Leave ${server.name}?',
      message:
          'This removes the server and its keys from this device. You will '
          'need a new invite to rejoin.',
      confirmLabel: 'Leave',
      icon: Icons.logout_rounded,
      isDestructive: true,
    );
    if (!confirmed) return;
    serverCubit.removeServer(server.id);
  }
}
