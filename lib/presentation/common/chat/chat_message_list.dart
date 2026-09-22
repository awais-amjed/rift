import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';

import '../../../data/classes/chat_message.dart';
import '../../../logic/helper_methods.dart';
import '../../../logic/services/quote_lookup.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';
import 'attachments/attachment_loader.dart';
import 'date_divider.dart';
import 'history_window_bar.dart';
import 'message_jump.dart';
import 'message_row/chat_message_row.dart';
import 'message_row/message_reply_quote.dart';

part 'chat_message_list_jumps.dart';
part 'chat_message_list_quotes.dart';

/// Scrollable message history, newest at the bottom (reversed list, so it
/// stays pinned to the latest message). Consecutive messages from the same
/// author within [groupWindow] collapse under one header, Discord-style, and a
/// day divider is inserted whenever the calendar date changes.
///
/// Freshly-arrived incoming messages animate in (fade + slide). Give the list
/// a `ValueKey` per conversation/channel so switching chats starts a new
/// animation-tracking state instead of animating the whole history at once.
///
/// Over the widget budget and one job: the list of rows, their day dividers and
/// which of them animate in. Looking up quoted messages and jumping to them are
/// its two parts.
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

  /// Look up a message a reply names but that is not in [messages] — older
  /// than the loaded page, or deleted. Null leaves those quotes unresolved,
  /// which is the honest rendering when nothing can ask.
  final Future<QuotedMessage> Function(String messageId)? onLookUpOriginal;

  /// Load a window of history around a message that is not in [messages],
  /// replacing the list with it. Answers whether it got there.
  final Future<bool> Function(String messageId)? onShowAround;

  /// Whether [messages] is a window into history rather than the live end.
  /// Draws the way back — see [HistoryWindowBar].
  final bool viewingHistory;
  final Future<void> Function()? onReturnToPresent;

  /// Open a message author's profile. Null on a surface with no profile to
  /// show — and never called for a row a webhook wrote, which carries a name
  /// rather than an account.
  ///
  /// Takes the id *and* the name because the two chat tiers answer
  /// differently: a server asks its roster, and a central DM has only the two
  /// people in it. The surface knows which it is.
  final void Function(String userId, String name)? onOpenProfile;

  /// Start a reply to a message. Null disables replying on this surface.
  final void Function(ChatMessage message)? onReply;

  /// Carry a message into another conversation. Null disables forwarding.
  final void Function(ChatMessage message)? onForward;

  /// Re-seal a message with new text. Null disables editing on this surface.
  final void Function(String messageId, String text)? onEdit;

  /// Hard-delete a message. Null disables deletion on this surface.
  final void Function(String messageId)? onDelete;

  /// Send a message that failed on the way out again. Null leaves a failed row
  /// saying so with nothing to press — which is still better than the row not
  /// being there.
  final void Function(String pendingId)? onRetry;

  /// Somebody pressed something on a bot's panel.
  final void Function(String messageId, String action, String? value)?
  onPanelAction;

  /// Whether the local user may delete other people's messages here
  /// (channel manager / server admin). Always false in DMs.
  final bool isModerator;

  /// Lower-cased names an `@mention` can reach on this surface.
  ///
  /// Supplied by the surface rather than looked up here, because only the
  /// surface knows who is reachable: a channel has a roster, and a central DM
  /// has one other person. Empty means every `@name` stays plain text, which
  /// is the honest default — a highlight promises somebody was pinged.
  final Set<String> mentionable;

  /// Username → display name, for drawing a mention as the name the room knows.
  /// A username missing from this is left as written — see `messageMarkupSpan`.
  final Map<String, String> mentionNames;

  /// What an empty conversation says. The default invites the first message,
  /// which is right almost everywhere — but a central request has no composer
  /// under it, and "say hi" printed above a note explaining that you cannot is
  /// the screen arguing with itself.
  final String emptyMessage;

  const ChatMessageList({
    super.key,
    this.emptyMessage = 'No messages yet — say hi!',
    required this.messages,
    this.controller,
    this.attachmentLoader,
    this.onToggleReaction,
    this.onLookUpOriginal,
    this.onShowAround,
    this.viewingHistory = false,
    this.onReturnToPresent,
    this.onOpenProfile,
    this.onReply,
    this.onForward,
    this.onEdit,
    this.onDelete,
    this.onRetry,
    this.onPanelAction,
    this.isModerator = false,
    this.mentionable = const {},
    this.mentionNames = const {},
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList>
    with _MessageListQuotesMixin, _MessageListJumpsMixin {
  /// Ids we've already rendered — used to decide which rows are new enough to
  /// animate. The first populated frame primes this set silently.
  final Set<String> _seen = <String>{};

  /// Highest server id seen so far. Live messages exceed it; a back-filled
  /// history page (scroll-up pagination) does not — so scrolling never
  /// animates old rows in.
  int _maxSeenId = 0;

  /// Where a row sits in the list, 0 at the end the scroll starts from.
  ///
  /// The list is reversed, so index 0 — the oldest message — is the far end,
  /// and this counts from the other side. Rows are not all the same height,
  /// so this is a guess; [MessageJumper] is built around correcting it.
  @override
  double? _fractionOf(String rowId) {
    final items = _buildItems();
    final index = items.indexWhere(
      (item) => item is _MsgItem && item.message.rowId == rowId,
    );
    if (index < 0 || items.length < 2) return null;
    return (items.length - 1 - index) / (items.length - 1);
  }

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
          prev.groupKey != cur.groupKey ||
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

  /// Messages that have just turned up, but only once the list has been
  /// populated at least once (so opening a chat doesn't animate the whole
  /// backlog). Also records every current id as seen.
  ///
  /// Two ways in, because there are two ways a message appears. One is
  /// somebody else's arriving at the live tail. The other is your own going up
  /// the moment you press enter — optimistically, before the server has said
  /// anything — which has no latency to cover but is still a row coming out of
  /// nothing, and read exactly like the pop it is.
  ///
  /// The acked copy that lands a moment later is deliberately not a third way:
  /// it is the same row getting its real id, and animating it would replay an
  /// arrival that already happened.
  Set<String> _computeAnimating() {
    final animate = <String>{};
    final primed = _seen.isNotEmpty;
    final prevMax = _maxSeenId;
    for (final m in widget.messages) {
      final isNew = _seen.add(m.id);
      final numericId = int.tryParse(m.id);
      if (numericId != null && numericId > _maxSeenId) _maxSeenId = numericId;
      if (!isNew || !primed) continue;

      final mineGoingUp = m.isMine && m.isPending;
      // Numeric and past the high-water mark: at the live tail, rather than a
      // page of history scrolled in from above.
      final theirsArriving =
          !m.isMine && numericId != null && numericId > prevMax;
      if (mineGoingUp || theirsArriving) animate.add(m.id);
    }
    return animate;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    if (widget.messages.isEmpty) {
      return Center(
        child: Text(
          widget.emptyMessage,
          style: AppText.body.copyWith(color: themeState.textTertiary),
        ),
      );
    }

    final items = _buildItems();
    // Built once per frame rather than searched per row: a list of five
    // hundred messages where most are replies is otherwise a scan of the
    // whole history for every row the viewport builds.
    final byId = {for (final m in widget.messages) m.id: m};
    _jumper.keepOnly({for (final m in widget.messages) m.rowId});

    // In the column rather than floating over it. A bar that takes
    // layout space normally means the conversation jumps when it
    // appears — but this one appears and leaves only when the list is
    // being replaced wholesale anyway, so there is no reading to
    // interrupt, and floating it put the pill on top of the newest
    // message in the window.
    return Column(
      children: [
        Expanded(child: _buildList(items, byId)),
        if (widget.viewingHistory && widget.onReturnToPresent != null)
          HistoryWindowBar(onReturn: () => unawaited(_returnToPresent())),
      ],
    );
  }

  Widget _buildList(List<_StreamItem> items, Map<String, ChatMessage> byId) {
    return ListView.builder(
      controller: widget.controller,
      reverse: true,
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      itemCount: items.length,
      itemBuilder: (context, reversedIndex) {
        final item = items[items.length - 1 - reversedIndex];
        if (item is _DateItem) {
          return DateDivider(label: item.label);
        }
        final msg = (item as _MsgItem).message;
        final origin = _originOf(msg, byId);
        // The GlobalKey goes on a wrapper, not on the row. It exists
        // only to give [MessageJumper] something to scroll to, and the
        // row's own key is load-bearing for a different reason — see
        // below. One widget cannot carry both.
        return KeyedSubtree(
          key: _jumper.keyFor(msg.rowId),
          child: ChatMessageRow(
            // Not `msg.id`: your own message is drawn under a local id and
            // then handed the server's, and keying by that would make the
            // ack destroy the row mid-entrance. See [ChatMessage.rowId].
            key: ValueKey(msg.rowId),
            message: msg,
            showHeader: item.showHeader,

            attachmentLoader: widget.attachmentLoader,
            onToggleReaction: widget.onToggleReaction,
            // A webhook's row names whoever it was told to name, so there is
            // no account behind it to open — see [MessageOriginBadge].
            onOpenProfile: widget.onOpenProfile == null || !msg.origin.isMember
                ? null
                : () => widget.onOpenProfile!(msg.authorId, msg.authorName),
            onReply: widget.onReply,
            onForward: widget.onForward,
            repliedTo: origin.original,
            originState: origin.state,
            // Pressable whenever there is a message to go to, whether it
            // is in the list or a few pages back. Not when there is
            // nothing — a line saying it was deleted is not a button.
            onJumpToOriginal: switch (origin.state) {
              ReplyOriginState.present => () => unawaited(
                _goToOriginal(msg.replyToId!, loaded: true),
              ),
              ReplyOriginState.behind when widget.onShowAround != null =>
                () => unawaited(_goToOriginal(msg.replyToId!, loaded: false)),
              _ => null,
            },
            flashToken: msg.rowId == _flashRowId ? _flashToken : null,
            onEdit: widget.onEdit,
            onDelete: widget.onDelete,
            onRetry: widget.onRetry,
            onPanelAction: widget.onPanelAction,
            isModerator: widget.isModerator,
            mentionable: widget.mentionable,
            mentionNames: widget.mentionNames,
            animateIn: _animating.contains(msg.id),
          ),
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
