import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'attachment_loader.dart';
import 'message_attachments.dart';
import 'message_reactions_bar.dart';

/// One message in the chat list — flat Discord-style row, not a bubble.
///
/// [showHeader] rows carry the avatar + author name + timestamp; continuation
/// rows (same author, small gap) show only the indented text. Hovering reveals
/// the "add reaction" affordance (when [onToggleReaction] is wired).
class ChatMessageRow extends StatefulWidget {
  static const double _avatarSize = 34;
  static const double _gutterWidth = 48;

  final ChatMessage message;
  final bool showHeader;
  final ThemeState themeState;

  /// Fetches attachment bytes on demand. Null when the chat surface doesn't
  /// support attachments (then attachments simply aren't rendered).
  final AttachmentLoader? attachmentLoader;

  /// Toggle a reaction on this message. Null disables reactions on this surface.
  final void Function(String messageId, String emoji)? onToggleReaction;

  /// When true, the row fades + slides in once on first build (a freshly
  /// arrived incoming message). Continuation of existing rows never animates.
  final bool animateIn;

  const ChatMessageRow({
    super.key,
    required this.message,
    required this.showHeader,
    required this.themeState,
    this.attachmentLoader,
    this.onToggleReaction,
    this.animateIn = false,
  });

  @override
  State<ChatMessageRow> createState() => _ChatMessageRowState();
}

class _ChatMessageRowState extends State<ChatMessageRow> {
  bool _hovering = false;

  ChatMessage get message => widget.message;
  ThemeState get themeState => widget.themeState;

  String _timeLabel(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final hm = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    if (sameDay) return hm;
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} $hm';
  }

  bool get _reactionsEnabled =>
      widget.onToggleReaction != null && !message.isPending;

  void _toggle(String emoji) => widget.onToggleReaction?.call(message.id, emoji);

  @override
  Widget build(BuildContext context) {
    Widget row = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: _buildRow(),
    );
    if (!widget.animateIn) return row;
    // One-shot entrance: fade up over a short slide. TweenAnimationBuilder only
    // runs on first build (the end value never changes), so a later rebuild of
    // the same row — theme change, list scroll — won't replay it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: row,
    );
  }

  Widget _buildRow() {
    final showReactions = _reactionsEnabled &&
        (message.reactions.isNotEmpty || _hovering);

    return Opacity(
      opacity: message.isPending ? 0.5 : 1.0,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: widget.showHeader ? 10 : 1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: ChatMessageRow._gutterWidth,
              child: widget.showHeader ? _buildAvatar() : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showHeader)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              message.authorName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: message.isMine
                                    ? themeState.primary
                                    : themeState.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _timeLabel(message.sentAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: themeState.textQuaternary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.text.isNotEmpty)
                    SelectableText(
                      message.text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: themeState.textSecondary,
                      ),
                    ),
                  if (message.attachments.isNotEmpty &&
                      widget.attachmentLoader != null)
                    MessageAttachments(
                      attachments: message.attachments,
                      loader: widget.attachmentLoader!,
                      themeState: themeState,
                    ),
                  if (showReactions)
                    MessageReactionsBar(
                      reactions: message.reactions,
                      themeState: themeState,
                      onToggle: _toggle,
                      onAdd: () =>
                          showReactionPicker(context, themeState, _toggle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: ChatMessageRow._avatarSize,
      height: ChatMessageRow._avatarSize,
      decoration: BoxDecoration(
        color: themeState.bgActive,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        message.authorName.isNotEmpty
            ? message.authorName[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: themeState.textSecondary,
        ),
      ),
    );
  }
}
