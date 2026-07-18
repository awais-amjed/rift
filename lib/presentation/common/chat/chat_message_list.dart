import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import 'chat_message.dart';
import 'widgets/chat_message_row.dart';

/// Scrollable message history, newest at the bottom (reversed list, so it
/// stays pinned to the latest message). Consecutive messages from the same
/// author within [groupWindow] collapse under one header, Discord-style.
class ChatMessageList extends StatelessWidget {
  static const groupWindow = Duration(minutes: 5);

  /// Messages ordered oldest → newest.
  final List<ChatMessage> messages;
  final ScrollController? controller;

  const ChatMessageList({super.key, required this.messages, this.controller});

  bool _showHeader(int index) {
    if (index == 0) return true;
    final prev = messages[index - 1];
    final curr = messages[index];
    return prev.authorId != curr.authorId ||
        curr.sentAt.difference(prev.sentAt) > groupWindow;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        if (messages.isEmpty) {
          return Center(
            child: Text(
              'No messages yet — say hi!',
              style: TextStyle(
                fontSize: 14,
                color: themeState.textTertiary,
              ),
            ),
          );
        }

        return ListView.builder(
          controller: controller,
          reverse: true,
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          itemCount: messages.length,
          itemBuilder: (context, reversedIndex) {
            final index = messages.length - 1 - reversedIndex;
            return ChatMessageRow(
              message: messages[index],
              showHeader: _showHeader(index),
              themeState: themeState,
            );
          },
        );
      },
    );
  }
}
