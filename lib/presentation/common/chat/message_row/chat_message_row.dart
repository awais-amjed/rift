import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../attachments/attachment_loader.dart';
import '../attachments/message_attachments.dart';
import '../reactions/message_reactions_bar.dart';
import '../reactions/reaction_picker.dart';
import 'message_hover_toolbar.dart';
import 'message_row_avatar.dart';
import 'message_row_header.dart';

/// One message in the chat list — flat Discord-style row, not a bubble.
///
/// [showHeader] rows carry the avatar + author name + timestamp; continuation
/// rows (same author, small gap) show only the indented text. Hovering lights
/// the whole row and reveals an action toolbar (react + copy).
class ChatMessageRow extends StatefulWidget {
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

  bool get _canReact => widget.onToggleReaction != null && !message.isPending;
  bool get _canCopy => message.text.isNotEmpty;
  bool get _showToolbar =>
      _hovering && !message.isPending && (_canReact || _canCopy);

  void _toggle(String emoji) =>
      widget.onToggleReaction?.call(message.id, emoji);

  void _pickReaction(BuildContext anchorContext) =>
      showReactionPicker(anchorContext, themeState, _toggle);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: message.text));
    HelperMethods.showToast(title: 'Copied', description: 'Message copied.');
  }

  @override
  Widget build(BuildContext context) {
    final content = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildRow(),
          if (_showToolbar)
            Positioned(
              top: -10,
              right: 14,
              child: MessageHoverToolbar(
                themeState: themeState,
                onReact: _canReact ? _pickReaction : null,
                onCopy: _canCopy ? (_) => _copy() : null,
              ),
            ),
        ],
      ),
    );

    if (!widget.animateIn) return content;
    // One-shot entrance: fade up over a short slide. TweenAnimationBuilder only
    // runs on first build (the end value never changes), so a later rebuild of
    // the same row — theme change, list scroll — won't replay it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: content,
    );
  }

  Widget _buildRow() {
    return Container(
      color: _hovering ? themeState.bgHover : Colors.transparent,
      child: Opacity(
        opacity: message.isPending ? 0.6 : 1.0,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: widget.showHeader ? 8 : 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ChatMessageRow._gutterWidth,
                child: widget.showHeader
                    ? MessageRowAvatar(
                        authorName: message.authorName,
                        themeState: themeState,
                      )
                    : null,
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final showReactions = _canReact && message.reactions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader)
          MessageRowHeader(message: message, themeState: themeState),
        if (message.text.isNotEmpty)
          SelectableText(
            message.text,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: themeState.textSecondary,
            ),
          ),
        if (message.attachments.isNotEmpty && widget.attachmentLoader != null)
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
            onAdd: _pickReaction,
          ),
      ],
    );
  }
}
