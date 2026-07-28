import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';

/// Header row of the chat pane: # channel-name + E2E badge + close button.
class ChatHeader extends StatelessWidget {
  const ChatHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final chatState = context.watch<ChannelChatCubit>().state;
    final channels =
        context.watch<ServerCubit>().state.selectedServer?.channels ?? [];

    final name = channels
        .where((c) => c.id == chatState.channelId)
        .map((c) => c.name)
        .firstOrNull;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        children: [
          Icon(Icons.tag, size: 18, color: themeState.textQuaternary),
          const SizedBox(width: 8),
          Text(
            name ?? 'channel',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: themeState.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Messages are end-to-end encrypted',
            child: Icon(
              Icons.lock_outline,
              size: 13,
              color: themeState.textQuaternary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => context.read<ChannelChatCubit>().closeChannel(),
            icon: Icon(Icons.close, size: 18, color: themeState.textTertiary),
            tooltip: 'Close chat',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
