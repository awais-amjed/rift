import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/notification_level.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_dropdown.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/notifications/notification_level_submenu.dart';
import '../../../../../common/quiet_danger_button.dart';
import '../../../../../common/server_scope.dart';
import '../../../invites/show_invite_modal.dart';
import '../../../profile/person/widgets/profile_section.dart';
import '../../leave_server.dart';
import '../../manage/server_manage_tab.dart';
import '../../manage/show_server_manage_dialog.dart';

/// What you can do about the server, beside what it is: ask people in,
/// manage it, choose how loud it is, and leave.
///
/// The same doors as its rail chip's menu, for somebody who came here
/// instead; each is offered on the same terms as there.
class ServerProfileActions extends StatelessWidget {
  final Server server;

  const ServerProfileActions({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    final permissions = server.user?.permissions;
    final level = context.select<ServerNotificationsCubit, NotificationLevel>(
      (c) => c.state.serverLevel(server.id),
    );
    // Wrapped, and not decoration: this column is laid out beside the
    // facts, so a lone `expanded` button would stretch to their height.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (permissions?.canCreateTokens ?? false)
          AppButton(
            label: 'Invite people',
            expanded: true,
            icon: const Icon(Icons.person_add_outlined, size: K.iconRow),
            onPressed: () => _replaceWith(
              context,
              (ctx) => inviteModal(ctx, server: server),
            ),
          ),
        // Asked of the dialog rather than of a permission, as the chip's
        // menu does: a member who may manage only the soundboard has a page.
        if (ServerManageTabs.visible(permissions).isNotEmpty)
          AppButton(
            label: 'Manage server',
            variant: AppButtonVariant.secondary,
            expanded: true,
            icon: const Icon(Icons.settings_outlined, size: K.iconRow),
            onPressed: () => _replaceWith(
              context,
              (ctx) => serverManageDialog(ctx, server: server),
            ),
          ),
        ProfileSection(
          label: 'Notify me about',
          child: AppDropdown<NotificationLevel>(
            value: level,
            icon: NotificationLevelSubmenu.iconFor(level),
            options: [
              for (final choice in NotificationLevel.channelChoices)
                AppDropdownOption(value: choice, label: choice.label),
            ],
            onChanged: (choice) => context
                .read<ServerNotificationsCubit>()
                .setServerLevel(server.id, choice),
          ),
        ),
        const SizedBox(height: 4),
        QuietDangerButton(
          icon: Icons.logout_rounded,
          label: 'Leave server',
          onTap: () => leaveServer(
            context,
            server: server,
            beforeLeaving: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  /// Close the profile and open [build] in its place, rather than stacking
  /// a second dialog over it. Built first, while this context still holds
  /// the cubits it reads, and carried in this server's scope.
  void _replaceWith(BuildContext context, Widget Function(BuildContext) build) {
    final dialog = ServerScope.carry(context, build(context));
    final navigator = Navigator.of(context);
    navigator.pop();
    showCustomDialog<void>(context: navigator.context, build: (_) => dialog);
  }
}
