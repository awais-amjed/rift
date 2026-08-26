import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/enums/home_surface.dart';
import '../../../../../../data/enums/notification_level.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/nav_row.dart';
import '../../../../../common/unread_badge.dart';
import 'channel_context_menu.dart';

/// Tile for a text channel. Tapping opens its E2E chat in the center pane
/// (and tapping the open one closes it).
class TextChannelTile extends StatelessWidget {
  final Channel channel;

  const TextChannelTile({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChannelChatCubit, ChannelChatState>(
      buildWhen: (prev, curr) => prev.channelId != curr.channelId,
      builder: (context, chatState) {
        final isSelected = chatState.channelId == channel.id;
        // Unread count for this channel; a selected/open channel is read.
        final serverId = context.select<ServerCubit, String?>(
          (c) => c.state.selectedServerId,
        );
        final unread = (isSelected || serverId == null)
            ? 0
            : context.select<ServerNotificationsCubit, int>(
                (c) => c.state.unreadForChannel(serverId, channel.id),
              );
        final level = serverId == null
            ? NotificationLevel.channelDefault
            : context.select<ServerNotificationsCubit, NotificationLevel>(
                (c) => c.state.channelLevel(serverId, channel.id),
              );

        return ChannelContextMenu.wrap(
          context: context,
          channel: channel,
          child: NavRow(
            icon: Icons.tag_rounded,
            label: channel.name,
            isSelected: isSelected,
            // A muted channel is still unread — the name stays lifted, so it
            // is visible that something is in there. What it loses is the
            // loud pill, which is the part that reads as "you are wanted".
            isUnread: unread > 0,
            trailing: unread > 0
                ? UnreadBadge(
                    count: unread,
                    themeState: context.watch<ThemeCubit>().state,
                    isMuted: level.isMuted,
                  )
                : level.isMuted
                ? Icon(
                    Icons.notifications_off_outlined,
                    size: 13,
                    color: context.watch<ThemeCubit>().state.textTertiary,
                  )
                : null,
            onTap: () {
              // Opening a channel chat leaves the Home (DMs) surface.
              context.read<AppCubit>().setSurface(HomeSurface.server);
              final cubit = context.read<ChannelChatCubit>();
              if (isSelected) {
                cubit.closeChannel();
              } else {
                cubit.openChannel(channel.id);
              }
            },
          ),
        );
      },
    );
  }
}
