import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/chat_message.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import 'widgets/attachment_loader.dart';
import 'widgets/chat_message_row.dart';

/// Scrollable message history, newest at the bottom (reversed list, so it
/// stays pinned to the latest message). Consecutive messages from the same
/// author within [groupWindow] collapse under one header, Discord-style.
///
/// Freshly-arrived incoming messages animate in (fade + slide). Give the list
/// a `ValueKey` per conversation/channel so switching chats starts a new
/// animation-tracking state instead of animating the whole history at once.
class ChatMessageList extends StatefulWidget {
  static const groupWindow = Duration(minutes: 5);

  /// Messages ordered oldest → newest.
  final List<ChatMessage> messages;
  final ScrollController? controller;

  /// Fetches attachment bytes on demand (wired to the chat cubit). Null on
  /// surfaces without attachment support.
  final AttachmentLoader? attachmentLoader;

  /// Toggle a reaction on a message. Null disables reactions on this surface.
  final void Function(String messageId, String emoji)? onToggleReaction;

  const ChatMessageList({
    super.key,
    required this.messages,
    this.controller,
    this.attachmentLoader,
    this.onToggleReaction,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  /// Ids we've already rendered — used to decide which rows are new enough to
  /// animate. The first populated frame primes this set silently.
  final Set<String> _seen = <String>{};

  /// Highest server id seen so far. Live messages exceed it; a back-filled
  /// history page (scroll-up pagination) does not — so scrolling never
  /// animates old rows in.
  int _maxSeenId = 0;

  bool _showHeader(int index) {
    if (index == 0) return true;
    final prev = widget.messages[index - 1];
    final curr = widget.messages[index];
    return prev.authorId != curr.authorId ||
        curr.sentAt.difference(prev.sentAt) > ChatMessageList.groupWindow;
  }

  /// Ids to animate this build: newly-seen incoming messages, but only once the
  /// list has been populated at least once (so opening a chat doesn't animate
  /// the whole backlog). Also records every current id as seen.
  Set<String> _computeAnimating() {
    final animate = <String>{};
    final primed = _seen.isNotEmpty;
    final prevMax = _maxSeenId;
    for (final m in widget.messages) {
      final isNew = _seen.add(m.id);
      final numericId = int.tryParse(m.id);
      if (numericId != null && numericId > _maxSeenId) _maxSeenId = numericId;
      // Animate only genuinely-new incoming messages at the live tail.
      if (isNew &&
          primed &&
          !m.isMine &&
          numericId != null &&
          numericId > prevMax) {
        animate.add(m.id);
      }
    }
    return animate;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        if (widget.messages.isEmpty) {
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

        final animating = _computeAnimating();

        return ListView.builder(
          controller: widget.controller,
          reverse: true,
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          itemCount: widget.messages.length,
          itemBuilder: (context, reversedIndex) {
            final index = widget.messages.length - 1 - reversedIndex;
            final message = widget.messages[index];
            return ChatMessageRow(
              key: ValueKey(message.id),
              message: message,
              showHeader: _showHeader(index),
              themeState: themeState,
              attachmentLoader: widget.attachmentLoader,
              onToggleReaction: widget.onToggleReaction,
              animateIn: animating.contains(message.id),
            );
          },
        );
      },
    );
  }
}
