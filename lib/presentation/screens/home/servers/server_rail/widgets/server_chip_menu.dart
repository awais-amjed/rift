import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/enums/notification_level.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../common/notifications/notification_level_submenu.dart';
import '../../../../../common/squircle_avatar.dart';
import '../../../../../common/unread_badge.dart';
import '../../../invites/invite_modal.dart';
import '../../manage/server_manage_tab.dart';
import '../../manage/show_server_manage_dialog.dart';

/// Right-click menu on a rail chip.
///
/// This is where every action that acts on a server as a whole lives — how
/// loud it is, mark read, invite, manage members, settings, leave. They belong
/// on the chip for the server they act on, rather than in a dialog listing all
/// servers or in a toolbar above the channel list that costs every member
/// vertical space.
///
/// Notifications sits first and is the only item everybody gets. Muting here
/// quiets every channel and conversation on the server that has no level of
/// its own, which is visible immediately: those channel tiles pick up the
/// muted mark, because they resolve through the same chain.
///
/// **Every item is handed the server it acts on**, including the dialogs — they
/// take a [Server] and pass its id down, so none of them reads the selection.
/// That is what lets the menu work on a chip you are not currently looking at
/// without first navigating you there. Anything added here has to do the same.
class ServerChipMenu extends StatelessWidget {
  final Server server;

  const ServerChipMenu({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    final permissions = server.user?.permissions;
    final unread = context.select<ServerNotificationsCubit, int>(
      (c) => c.state.unreadForServer(server.id),
    );

    return ContextMenuPanel(
      maxWidth: 216,
      heading: 'Server',
      subheading: server.name,
      caption: Uri.tryParse(server.supabaseUrl)?.host,
      leading: SquircleAvatar(
        name: server.name,
        seed: server.id,
        imageUrl: server.iconUrl,
        size: 24,
      ),
      children: [
        NotificationLevelSubmenu(
          current: context.select<ServerNotificationsCubit, NotificationLevel>(
            (c) => c.state.serverLevel(server.id),
          ),
          onSelected: (level) {
            final notifications = context.read<ServerNotificationsCubit>();
            ContextMenuScope.of(context)?.call();
            notifications.setServerLevel(server.id, level);
          },
        ),
        if (unread > 0)
          ContextMenuItem(
            icon: Icons.mark_chat_read_outlined,
            label: 'Mark as read',
            trailing: UnreadBadge(count: unread),
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
            onTap: () => showDialogFromMenu(
              context: context,
              build: (ctx) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: ctx.read<ServerCubit>()),
                  BlocProvider.value(value: ctx.read<AppCubit>()),
                ],
                child: InviteModal(server: server),
              ),
            ),
          ),
        // Members for whoever moderates them; the whole dialog for whoever
        // runs the place. Both are the same dialog on a different page, and
        // the rest of it is one click to the left once there.
        if ((permissions?.isServerAdmin ?? false) ||
            (permissions?.isChannelManager ?? false))
          ContextMenuItem(
            icon: Icons.manage_accounts_outlined,
            label: 'Manage members',
            onTap: () => _manage(context, ServerManageTab.members),
          ),
        // Asked of the dialog rather than of a permission, because the
        // dialog is the only thing that knows what its pages need. Gated on
        // `isServerAdmin` this offered nothing to somebody holding one of
        // the narrower bits — a member who may manage the soundboard and
        // nothing else had a page and no door to it.
        if (ServerManageTabs.visible(permissions).isNotEmpty)
          ContextMenuItem(
            icon: Icons.settings_outlined,
            label: 'Manage server',
            // Open reports, for the server they belong to. On a phone this
            // is the only place a moderator would see them waiting: there is
            // no settings gear in the header to carry the count.
            trailing: switch (context.select<ReportsCubit, int>(
              (c) => c.state.openCount,
            )) {
              final n
                  when n > 0 &&
                      context.read<ServerCubit>().state.selectedServer?.id ==
                          server.id =>
                UnreadBadge(count: n),
              _ => null,
            },
            onTap: () => _manage(context, null),
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

  void _manage(BuildContext context, ServerManageTab? tab) =>
      showDialogFromMenu(
        context: context,
        build: (ctx) => serverManageDialog(ctx, server: server, initial: tab),
      );

  /// Leaving is local: the row on the server stays, and so does everything
  /// that row carries.
  ///
  /// Which is worth saying out loud to an **owner**, because for them the
  /// consequence is not "you need a new invite" — it is that the one person
  /// who can end the server or hand it on has walked out of the only place
  /// they could do either from. Nobody else can do it for them, and an invite
  /// back has to come from an admin who is still there. The danger zone
  /// already points at Transfer ownership; this is the other door into the
  /// same mistake.
  Future<void> _leave(BuildContext context) async {
    final dismiss = ContextMenuScope.of(context);
    final serverCubit = context.read<ServerCubit>();
    final host = context;
    final isOwner = server.user?.permissions.isOwner ?? false;
    dismiss?.call();

    final confirmed = await showConfirmDialog(
      context: host,
      title: 'Leave ${server.name}?',
      message: isOwner
          ? 'This removes the server and its keys from this device, but you '
                'stay its owner — and the owner is the only person who can '
                'end it or hand it on. Nobody left behind can do either, and '
                'getting back in needs an invite from an admin who is still '
                'there. To step down properly, open Members and choose '
                'Transfer ownership first.'
          : 'This removes the server and its keys from this device. You will '
                'need a new invite to rejoin.',
      confirmLabel: 'Leave',
      icon: Icons.logout_rounded,
      isDestructive: true,
    );
    if (!confirmed) return;
    serverCubit.removeServer(server.id);
  }
}
