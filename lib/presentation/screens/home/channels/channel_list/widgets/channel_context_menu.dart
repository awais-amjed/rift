import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../data/enums/notification_level.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../common/notifications/notification_level_submenu.dart';
import '../../../../../theme/theme_context.dart';
import '../../settings/channel_settings_tab.dart';
import 'channel_menu_actions.dart';

/// Right-click menu for a channel in the sidebar — how loud it is, who can
/// see it, and, for whoever may manage it, its settings and delete.
///
/// It used to be channel managers only, on the reasoning that a member's menu
/// would be a menu of refusals. That stopped being true the moment a member
/// got something of their own to set here: how much this channel is allowed to
/// interrupt them is nobody's business but theirs, and it is the only item
/// most people will ever open this menu for. So everyone gets the menu, and
/// the manager items are what's conditional.
class ChannelContextMenu extends StatelessWidget {
  final Channel channel;

  const ChannelContextMenu({super.key, required this.channel});

  /// Wraps [child] in the menu. Everyone gets one — see the class comment for
  /// why this stopped being a permission check.
  static Widget wrap({
    required BuildContext context,
    required Channel channel,
    required Widget child,
  }) => ContextMenuRegion(
    contextMenu: ChannelContextMenu(channel: channel),
    child: child,
  );

  Future<void> _delete(BuildContext context) async {
    ContextMenuScope.of(context)?.call();
    await deleteChannel(context, channel);
  }

  void _setLevel(BuildContext context, NotificationLevel level) {
    final serverId = context.read<ServerCubit>().state.selectedServerId;
    final notifications = context.read<ServerNotificationsCubit>();
    ContextMenuScope.of(context)?.call();
    if (serverId == null) return;
    notifications.setChannelLevel(serverId, channel.id, level);
  }

  @override
  Widget build(BuildContext context) {
    final isVoice = channel.channelType == ChannelType.voice;
    final serverId = context.watch<ServerCubit>().state.selectedServerId;
    final canManage = canManageChannel(context, channel);

    return ContextMenuPanel(
      heading: isVoice ? 'Voice channel' : 'Text channel',
      subheading: channel.name,
      leading: Icon(
        isVoice ? Icons.volume_up_rounded : Icons.tag_rounded,
        size: K.iconRow,
        color: context.theme.textTertiary,
      ),
      children: [
        // Voice channels have no messages, so there is nothing here to be
        // notified about and a menu row that did nothing would be worse than
        // no row.
        if (!isVoice && serverId != null)
          NotificationLevelSubmenu(
            current: context
                .watch<ServerNotificationsCubit>()
                .state
                .channelLevel(serverId, channel.id),
            onSelected: (level) => _setLevel(context, level),
          ),
        // Every member of a private channel may read its member list, not just
        // whoever runs it: knowing who else can read what you are about to say
        // is the point of the room being private.
        if (channel.isPrivate)
          ContextMenuItem(
            icon: Icons.group_outlined,
            label: 'Who can see this',
            onTap: () => openChannelSettings(
              context,
              channel,
              initial: ChannelSettingsTab.access,
            ),
          ),
        // Privacy, bots and webhooks live in the settings now, a page each;
        // the menu keeps what is quick or is the member's own.
        if (canManage)
          ContextMenuItem(
            icon: Icons.settings_outlined,
            label: 'Channel settings',
            onTap: () => openChannelSettings(context, channel),
          ),
        // Leaving is not a manager's act, so it is not behind the manager
        // check: being able to walk out of a room you were put in needs
        // nobody's permission.
        if (channel.isPrivate)
          ContextMenuItem(
            icon: Icons.logout_rounded,
            label: 'Leave channel',
            isDangerous: true,
            onTap: () => leaveChannel(context, channel),
          ),
        if (canManage)
          ContextMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Delete channel',
            isDangerous: true,
            onTap: () => _delete(context),
          ),
      ],
    );
  }
}
