import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';

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
            final unread = isSelected
                ? 0
                : context.select<ServerNotificationsCubit, int>(
                    (c) => c.state.unreadFor(channel.id),
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
                        _UnreadBadge(count: unread, themeState: themeState),
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

/// Small pill showing a channel's unread message count (capped at "99+").
class _UnreadBadge extends StatelessWidget {
  final int count;
  final ThemeState themeState;

  const _UnreadBadge({required this.count, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: themeState.primary,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: themeState.onPrimary,
        ),
      ),
    );
  }
}
