import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../data/enums/notification_level.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../common/notifications/notification_level_submenu.dart';
import '../../channel_settings_dialog.dart';
import '../../webhooks/channel_webhooks_dialog.dart';

/// Right-click menu for a channel in the sidebar — how loud it is, and, for
/// whoever may manage it, settings and delete.
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

  void _openSettings(BuildContext context) {
    showDialogFromMenu(
      context: context,
      build: (ctx) => BlocProvider.value(
        value: ctx.read<ServerCubit>(),
        child: ChannelSettingsDialog(channel: channel),
      ),
    );
  }

  void _openWebhooks(BuildContext context) {
    showDialogFromMenu(
      context: context,
      build: (ctx) => BlocProvider.value(
        value: ctx.read<ServerCubit>(),
        child: ChannelWebhooksDialog(channel: channel),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    ContextMenuScope.of(context)?.call();
    final serverCubit = context.read<ServerCubit>();
    final isVoice = channel.channelType == ChannelType.voice;

    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete #${channel.name}?',
      message: isVoice
          ? 'Anyone in this call will be disconnected. The channel and its '
                'history are gone for everyone, and this cannot be undone.'
          : 'The channel and every message in it are gone for everyone, and '
                'this cannot be undone.',
      confirmLabel: 'Delete channel',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed) return;

    final result = await serverCubit.deleteChannel(channel.id);
    if (!result.success) {
      HelperMethods.showError(
        error: result.error ?? 'Could not delete that channel',
      );
    }
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
    final canManage =
        context
            .watch<ServerCubit>()
            .state
            .selectedServer
            ?.user
            ?.permissions
            .isChannelManager ??
        false;

    return ContextMenuPanel(
      heading: isVoice ? 'Voice channel' : 'Text channel',
      subheading: channel.name,
      leading: Icon(
        isVoice ? Icons.volume_up_rounded : Icons.tag_rounded,
        size: 16,
        color: context.watch<ThemeCubit>().state.textTertiary,
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
        if (canManage) ...[
          ContextMenuItem(
            icon: Icons.tune_rounded,
            label: 'Settings',
            onTap: () => _openSettings(context),
          ),
          // Text channels only: a webhook posts a message, and a voice channel
          // has nowhere to put one.
          if (!isVoice)
            ContextMenuItem(
              icon: Icons.webhook_rounded,
              label: 'Webhooks',
              onTap: () => _openWebhooks(context),
            ),
          ContextMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Delete channel',
            isDangerous: true,
            onTap: () => _delete(context),
          ),
        ],
      ],
    );
  }
}
