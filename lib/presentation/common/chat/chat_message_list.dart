import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../data/classes/chat_message.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import 'attachments/attachment_loader.dart';
import 'date_divider.dart';
import 'message_row/chat_message_row.dart';
import '../../theme/app_text.dart';

/// Scrollable message history, newest at the bottom (reversed list, so it
/// stays pinned to the latest message). Consecutive messages from the same
/// author within [groupWindow] collapse under one header, Discord-style, and a
/// day divider is inserted whenever the calendar date changes.
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

  /// Re-seal a message with new text. Null disables editing on this surface.
  final void Function(String messageId, String text)? onEdit;

  /// Hard-delete a message. Null disables deletion on this surface.
  final void Function(String messageId)? onDelete;

  /// Whether the local user may delete other people's messages here
  /// (channel manager / server admin). Always false in DMs.
  final bool isModerator;

  const ChatMessageList({
    super.key,
    required this.messages,
    this.controller,
    this.attachmentLoader,
    this.onToggleReaction,
    this.onEdit,
    this.onDelete,
    this.isModerator = false,
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

  /// Build the flat render list: messages interleaved with day dividers, each
  /// message tagged with whether it opens a group (shows avatar + header).
  List<_StreamItem> _buildItems() {
    final items = <_StreamItem>[];
    for (var i = 0; i < widget.messages.length; i++) {
      final cur = widget.messages[i];
      final prev = i > 0 ? widget.messages[i - 1] : null;
      final newDay =
          prev == null ||
          !_sameDay(prev.sentAt.toLocal(), cur.sentAt.toLocal());
      if (newDay) items.add(_DateItem(_dayLabel(cur.sentAt.toLocal())));

      // When it's not a new day, prev is guaranteed non-null (newDay covers it).
      final showHeader =
          newDay ||
          prev.authorId != cur.authorId ||
          cur.sentAt.difference(prev.sentAt) > ChatMessageList.groupWindow;
      items.add(_MsgItem(cur, showHeader));
    }
    return items;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(d); // weekday
    if (d.year == now.year) return DateFormat('EEEE, MMM d').format(d);
    return DateFormat('MMM d, yyyy').format(d);
  }

  /// Ids to animate, recomputed when the messages change rather than during
  /// build: the scan also *records* what it has seen, and a build that runs
  /// twice for one frame would consume the animation on the first pass and
  /// render the second without it.
  Set<String> _animating = const {};

  @override
  void initState() {
    super.initState();
    _animating = _computeAnimating();
  }

  @override
  void didUpdateWidget(ChatMessageList old) {
    super.didUpdateWidget(old);
    if (!identical(old.messages, widget.messages)) {
      _animating = _computeAnimating();
    }
  }

  /// Newly-seen incoming messages, but only once the list has been populated at
  /// least once (so opening a chat doesn't animate the whole backlog). Also
  /// records every current id as seen.
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
              style: AppText.body.copyWith(
                fontSize: 14,
                color: themeState.textTertiary,
              ),
            ),
          );
        }

        final items = _buildItems();

        return ListView.builder(
          controller: widget.controller,
          reverse: true,
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          itemCount: items.length,
          itemBuilder: (context, reversedIndex) {
            final item = items[items.length - 1 - reversedIndex];
            if (item is _DateItem) {
              return DateDivider(label: item.label, themeState: themeState);
            }
            final msg = (item as _MsgItem).message;
            return ChatMessageRow(
              key: ValueKey(msg.id),
              message: msg,
              showHeader: item.showHeader,
              themeState: themeState,
              attachmentLoader: widget.attachmentLoader,
              onToggleReaction: widget.onToggleReaction,
              onEdit: widget.onEdit,
              onDelete: widget.onDelete,
              isModerator: widget.isModerator,
              animateIn: _animating.contains(msg.id),
            );
          },
        );
      },
    );
  }
}

/// An item in the flattened render list — a message or a day divider.
sealed class _StreamItem {}

class _DateItem extends _StreamItem {
  final String label;
  _DateItem(this.label);
}

class _MsgItem extends _StreamItem {
  final ChatMessage message;
  final bool showHeader;
  _MsgItem(this.message, this.showHeader);
}
