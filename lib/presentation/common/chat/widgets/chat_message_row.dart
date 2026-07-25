import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import 'attachment_loader.dart';
import 'message_attachments.dart';
import 'message_reactions_bar.dart';

/// One message in the chat list — flat Discord-style row, not a bubble.
///
/// [showHeader] rows carry the avatar + author name + timestamp; continuation
/// rows (same author, small gap) show only the indented text. Hovering lights
/// the whole row and reveals an action toolbar (react + copy).
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

  bool get _canReact =>
      widget.onToggleReaction != null && !message.isPending;
  bool get _canCopy => message.text.isNotEmpty;
  bool get _showToolbar =>
      _hovering && !message.isPending && (_canReact || _canCopy);

  String _timeLabel(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _toggle(String emoji) => widget.onToggleReaction?.call(message.id, emoji);

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
            Positioned(top: -10, right: 14, child: _buildToolbar()),
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
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: content,
    );
  }

  Widget _buildRow() {
    final showReactions =
        _canReact && message.reactions.isNotEmpty;

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
                child: widget.showHeader ? _buildAvatar() : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showHeader) _buildMeta(),
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
                        onAdd: (anchorCtx) =>
                            showReactionPicker(anchorCtx, themeState, _toggle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeta() {
    return Padding(
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
          if (message.isPending)
            Row(
              children: [
                SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: themeState.textQuaternary,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Sending…',
                  style: TextStyle(
                    fontSize: 11,
                    color: themeState.textQuaternary,
                  ),
                ),
              ],
            )
          else
            Text(
              _timeLabel(message.sentAt),
              style: TextStyle(fontSize: 11, color: themeState.textQuaternary),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: themeState.bgElevated,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: themeState.borderPrimary),
        ),
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canReact)
              _ToolbarButton(
                icon: Icons.add_reaction_outlined,
                tooltip: 'React',
                themeState: themeState,
                onTap: (anchorCtx) =>
                    showReactionPicker(anchorCtx, themeState, _toggle),
              ),
            if (_canCopy)
              _ToolbarButton(
                icon: Icons.content_copy_rounded,
                tooltip: 'Copy text',
                themeState: themeState,
                onTap: (_) => _copy(),
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

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final ThemeState themeState;
  final void Function(BuildContext anchorContext) onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onTap(context),
        borderRadius: BorderRadius.circular(7),
        hoverColor: themeState.bgHover,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: themeState.textTertiary),
        ),
      ),
    );
  }
}
