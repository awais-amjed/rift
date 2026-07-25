import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/unread_badge.dart';

/// Tile for displaying a text channel. Tapping opens its E2E chat in the
/// center pane (and tapping the open one closes it).
class TextChannelTile extends StatelessWidget {
  final Channel channel;

  const TextChannelTile({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<ChannelChatCubit, ChannelChatState>(
          buildWhen: (prev, curr) => prev.channelId != curr.channelId,
          builder: (context, chatState) {
            final isSelected = chatState.channelId == channel.id;
            // Unread count for this channel; a selected/open channel is read.
            final serverId =
                context.select<ServerCubit, String?>((c) => c.state.selectedServerId);
            final unread = (isSelected || serverId == null)
                ? 0
                : context.select<ServerNotificationsCubit, int>(
                    (c) => c.state.unreadForChannel(serverId, channel.id),
                  );
            final hasUnread = unread > 0;

            return Material(
              color:
                  isSelected ? themeState.channelActiveBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                hoverColor: themeState.bgHover,
                onTap: () {
                  // Opening a channel chat leaves the Home (DMs) surface.
                  context.read<AppCubit>().setHomeViewOpen(false);
                  final cubit = context.read<ChannelChatCubit>();
                  if (isSelected) {
                    cubit.closeChannel();
                  } else {
                    cubit.openChannel(channel.id);
                  }
                },
                child: Container(
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border.all(
                            color: themeState.channelActiveBorder,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        )
                      : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tag,
                        size: 17,
                        color: isSelected
                            ? themeState.primary
                            : (hasUnread
                                ? themeState.textPrimary
                                : themeState.textQuaternary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          channel.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? themeState.channelActiveText
                                : (hasUnread
                                    ? themeState.textPrimary
                                    : themeState.textSecondary),
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        UnreadBadge(count: unread, themeState: themeState),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
