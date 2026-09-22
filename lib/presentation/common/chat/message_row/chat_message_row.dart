import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/forwarding/forward_payload.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../../logic/services/message_permissions.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../confirm_dialog.dart';
import '../../message_markup_text.dart';
import '../attachments/attachment_loader.dart';
import '../attachments/message_attachments.dart';
import '../link_preview_card.dart';
import '../panel/panel_view.dart';
import '../reactions/message_reactions_bar.dart';
import '../reactions/reaction_picker.dart';
import 'guarded_message_text.dart';
import 'link_tap_recognizers.dart';
import 'message_action_sheet.dart';
import 'message_context_menu.dart';
import 'message_edit_field.dart';
import 'message_flash_highlight.dart';
import 'message_forwarded_card.dart';
import 'message_hover_toolbar.dart';
import 'message_locked_body.dart';
import 'message_reply_quote.dart';
import 'message_row_avatar.dart';
import 'message_row_header.dart';
import 'message_text.dart';

/// One message in the chat list — flat Discord-style row, not a bubble.
///
/// [showHeader] rows carry the avatar + author name + timestamp; continuation
/// rows (same author, small gap) show only the indented text. Hovering lights
/// the whole row and reveals an action toolbar (react + copy).
class ChatMessageRow extends StatefulWidget {
  static const double _gutterWidth = K.messageGutter;

  final ChatMessage message;
  final bool showHeader;

  /// Fetches attachment bytes on demand. Null when the chat surface doesn't
  /// support attachments (then attachments simply aren't rendered).
  final AttachmentLoader? attachmentLoader;

  /// Toggle a reaction on this message. Null disables reactions on this surface.
  final void Function(String messageId, String emoji)? onToggleReaction;

  /// Open the author's profile. Null where there is nobody to open: a
  /// webhook wrote the row, or the surface has no profile to show.
  final VoidCallback? onOpenProfile;

  /// Start a reply to this message. Null disables replying on this surface.
  final void Function(ChatMessage message)? onReply;

  /// Carry this message into another conversation. Null disables forwarding.
  final void Function(ChatMessage message)? onForward;

  /// Take the reader to the message this one answers. Null where the list
  /// cannot scroll, or where there is nothing loaded to scroll to.
  final VoidCallback? onJumpToOriginal;

  /// Set when a jump has just landed on this row, and changed on every jump
  /// so the same row can be flashed twice. See [MessageFlashHighlight].
  final int? flashToken;

  /// What the lookup for [repliedTo] found — see [ReplyOriginState].
  final ReplyOriginState originState;

  /// The message this one answers, already decrypted and verified by this
  /// client, or null when the reference points at something it cannot show.
  ///
  /// Only ever read when [ChatMessage.isReply]; a null here with a reply id
  /// above it is the "original unavailable" case, which is a different row
  /// from one that is not a reply at all.
  final ChatMessage? repliedTo;

  /// Re-seal this message with new text. Null disables editing.
  final void Function(String messageId, String text)? onEdit;

  /// Hard-delete this message. Null disables deletion.
  final void Function(String messageId)? onDelete;

  /// Send a failed message again. Null on a surface with no outbox — the row
  /// still says "Not sent", it just has nothing to offer.
  final void Function(String pendingId)? onRetry;

  /// Somebody pressed something on a bot's panel. Null where the surface has
  /// no way to send one — a panel is still worth reading where it cannot be
  /// touched, so the buttons are drawn and inert rather than hidden.
  final void Function(String messageId, String action, String? value)?
  onPanelAction;

  /// Whether the local user may delete *other* people's messages here.
  final bool isModerator;

  /// Lower-cased names an `@mention` can reach — see [ChatMessageList].
  final Set<String> mentionable;

  /// Username → display name, for drawing a mention as the name the room knows.
  /// A username missing from this is left as written — see `messageMarkupSpan`.
  final Map<String, String> mentionNames;

  /// When true, the row fades + slides in once on first build (a freshly
  /// arrived incoming message). Continuation of existing rows never animates.
  final bool animateIn;

  const ChatMessageRow({
    super.key,
    required this.message,
    required this.showHeader,
    this.attachmentLoader,
    this.onToggleReaction,
    this.onOpenProfile,
    this.onReply,
    this.onForward,
    this.onJumpToOriginal,
    this.flashToken,
    this.originState = ReplyOriginState.present,
    this.repliedTo,
    this.onEdit,
    this.onDelete,
    this.onRetry,
    this.onPanelAction,
    this.isModerator = false,
    this.mentionable = const {},
    this.mentionNames = const {},
    this.animateIn = false,
  });

  @override
  State<ChatMessageRow> createState() => _ChatMessageRowState();
}

class _ChatMessageRowState extends State<ChatMessageRow> {
  /// The tap handlers behind this message's links. Remade each build, so
  /// an edited body does not keep answering with yesterday's addresses.
  final LinkTapRecognizers _links = LinkTapRecognizers();

  @override
  void dispose() {
    _links.dispose();
    super.dispose();
  }

  /// Whether to play the entrance, decided once when the row is created.
  ///
  /// Read here rather than from `widget` at build time: your own message is
  /// told it is new while it is pending and not once it is acked, and a row
  /// that re-read the answer would snap to the end of its own entrance the
  /// moment the server replied.
  late final bool _entering = widget.animateIn;

  bool _hovering = false;
  bool _editing = false;

  ChatMessage get message => widget.message;
  ThemeState get themeState => context.theme;

  bool get _canReact =>
      widget.onToggleReaction != null &&
      !message.isPending &&
      // Reacting to a message you cannot read is a mis-click waiting to
      // happen, and the tally would be visible to everyone who can.
      !message.isLocked;
  bool get _canCopy => message.text.isNotEmpty;
  bool get _canReply =>
      widget.onReply != null &&
      !message.isPending &&
      // Answering something you cannot read yet would seal a reference to a
      // message whose author and content you are guessing at.
      !message.isLocked;
  bool get _canForward =>
      widget.onForward != null && ForwardPayload.canForward(message);
  bool get _canEdit =>
      widget.onEdit != null && MessagePermissions.canEdit(message);
  bool get _canDelete =>
      widget.onDelete != null &&
      MessagePermissions.canDelete(message, isModerator: widget.isModerator);
  bool get _showToolbar =>
      _hovering &&
      !_editing &&
      !message.isPending &&
      (_canReact ||
          _canReply ||
          _canForward ||
          _canCopy ||
          _canEdit ||
          _canDelete);

  void _toggle(String emoji) =>
      widget.onToggleReaction?.call(message.id, emoji);

  void _reply() => widget.onReply?.call(message);

  void _forward() => widget.onForward?.call(message);

  void _pickReaction(BuildContext anchorContext) =>
      showReactionPicker(anchorContext, themeState, _toggle);

  /// The touch way in. A long press is a right-click without a right button,
  /// and the buzz is the only sign it has registered — the menu opens after
  /// the press is held, so without it the finger spends half a second on a
  /// screen that looks like it is ignoring it.
  void _openContextMenuByTouch(Offset position) {
    if (message.isPending) return;
    if (HostPlatform.isMobile) HapticFeedback.mediumImpact();
    unawaited(_openContextMenu(position));
  }

  /// Whether the menu is up. A right-click reaches this twice on a row whose
  /// text holds a mention: the text's own listener answers the pointer-down
  /// and, with a mention span breaking the selection recognizer's hold on the
  /// gesture, the row's detector answers the same click as a secondary tap.
  /// Two menus then stack, and it takes two clicks to be rid of them.
  bool _menuOpen = false;

  Future<void> _openContextMenu(Offset position) async {
    if (message.isPending || _menuOpen) return;
    _menuOpen = true;
    try {
      await _showContextMenu(position);
    } finally {
      _menuOpen = false;
    }
  }

  Future<void> _showContextMenu(Offset position) async {
    if (context.layoutMode.isCompact) return _showActionSheet();
    final action = await showMessageContextMenu(
      context: context,
      position: position,
      themeState: themeState,
      message: message,
      canReact: _canReact,
      canReply: _canReply,
      canForward: _canForward,
      canEdit: _canEdit,
      canDelete: _canDelete,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case MessageMenuAction.reply:
        _reply();
      case MessageMenuAction.forward:
        _forward();
      case MessageMenuAction.react:
        // Anchored to the row rather than to the menu entry, which is gone by
        // the time this runs.
        _pickReaction(context);
      case MessageMenuAction.copy:
        await _copy();
      case MessageMenuAction.edit:
        setState(() => _editing = true);
      case MessageMenuAction.delete:
        await _confirmDelete();
    }
  }

  /// A phone's long press: the same actions as a sheet, with the quick
  /// reactions across its top, and the full picker behind "Add reaction".
  Future<void> _showActionSheet() async {
    final choice = await showMessageActionSheet(
      context: context,
      message: message,
      canReact: _canReact,
      canReply: _canReply,
      canForward: _canForward,
      canEdit: _canEdit,
      canDelete: _canDelete,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case QuickReaction(:final emoji):
        _toggle(emoji);
      case MenuActionChoice(action: MessageMenuAction.reply):
        _reply();
      case MenuActionChoice(action: MessageMenuAction.forward):
        _forward();
      case MenuActionChoice(action: MessageMenuAction.react):
        final emoji = await showEmojiReactionSheet(context);
        if (mounted && emoji != null) _toggle(emoji);
      case MenuActionChoice(action: MessageMenuAction.copy):
        await _copy();
      case MenuActionChoice(action: MessageMenuAction.edit):
        setState(() => _editing = true);
      case MenuActionChoice(action: MessageMenuAction.delete):
        await _confirmDelete();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete message?',
      message: message.text.isNotEmpty
          ? 'This removes it for everyone. It cannot be undone.'
          : 'This removes the attachment for everyone. It cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed) return;
    widget.onDelete?.call(message.id);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: message.text));
    HelperMethods.showToast(title: 'Copied', description: 'Message copied.');
  }

  @override
  Widget build(BuildContext context) {
    _links.reset();
    final content = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _openContextMenu(d.globalPosition),
        // Without this a message has no reachable actions at all on a phone:
        // the toolbar above waits for a hover that never comes, and the line
        // above waits for a mouse button that isn't there.
        onLongPressStart: (d) => _openContextMenuByTouch(d.globalPosition),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildRow(),
            // Over the row rather than behind it, so it tints the whole
            // line including the avatar gutter — the mark has to say
            // "this one", and half a row says "roughly here".
            Positioned.fill(
              child: MessageFlashHighlight(token: widget.flashToken),
            ),
            if (_showToolbar)
              Positioned(
                // Lifted clear of the row and aligned with its text edge, so
                // the toolbar reads as belonging to this message rather than
                // floating between it and the one above.
                top: -12,
                right: K.messageRowHPad,
                // Rises the last few pixels into place rather than appearing
                // fully formed. Only on the way in: it leaves the moment the
                // pointer does, because a toolbar fading out under a cursor
                // that has already moved on is something to wait for, and the
                // one thing motion here must never be is something to wait
                // for.
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: AppMotion.react,
                  curve: AppMotion.settle,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 4),
                      child: child,
                    ),
                  ),
                  child: MessageHoverToolbar(
                    onReact: _canReact ? _pickReaction : null,
                    onReply: _canReply ? (_) => _reply() : null,
                    onForward: _canForward ? (_) => _forward() : null,
                    onCopy: _canCopy ? (_) => _copy() : null,
                    onEdit: _canEdit
                        ? (_) => setState(() => _editing = true)
                        : null,
                    onDelete: _canDelete ? (_) => _confirmDelete() : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!_entering) return content;
    // One-shot entrance: fade up over a short slide. TweenAnimationBuilder only
    // runs on first build (the end value never changes), so a later rebuild of
    // the same row — theme change, list scroll — won't replay it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.enter,
      curve: AppMotion.arrive,
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
      // Half the usual hover: a message list is mostly hover surface as the
      // pointer crosses it, and the full row fill turns reading into a
      // strobe. It only has to say "the toolbar belongs to this one".
      color: _hovering ? themeState.bgHoverSubtle : Colors.transparent,
      child: Opacity(
        // Dimmed while it is in flight, and full strength again once it has
        // failed: the fade says "not finished", and a row asking to be pressed
        // is the wrong thing to push into the background.
        opacity: message.isPending && !message.sendFailed ? 0.6 : 1.0,
        child: Padding(
          padding: EdgeInsets.only(
            left: K.messageRowHPad,
            right: K.messageRowHPad,
            top: widget.showHeader ? 7 : 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              SizedBox(
                width: ChatMessageRow._gutterWidth,
                child: widget.showHeader
                    ? _tappable(
                        MessageRowAvatar(
                          authorName: message.authorName,
                          authorId: message.authorId,
                          avatarPath: message.authorAvatarPath,
                        ),
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

  /// The avatar, clickable when there is a profile behind it.
  ///
  /// A plain [GestureDetector] rather than an ink well: the avatar is opaque
  /// and rounded, so a highlight underneath it would be painted and then
  /// covered. The pointer change is what says it is pressable.
  Widget _tappable(Widget child) {
    final open = widget.onOpenProfile;
    if (open == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: open, child: child),
    );
  }

  Widget _buildBody() {
    final showReactions = _canReact && message.reactions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Above the header, the way it is read: what is being answered, then
        // who is answering. Once per group — [ChatMessage.groupKey] carries
        // the reference for that reason.
        if (widget.showHeader && message.isReply)
          MessageReplyQuote(
            original: widget.repliedTo,
            state: widget.originState,
            onJump: widget.onJumpToOriginal,
          ),
        if (widget.showHeader)
          MessageRowHeader(
            message: message,
            onOpenProfile: widget.onOpenProfile,
            onRetry: widget.onRetry == null
                ? null
                : () => widget.onRetry!(message.id),
          ),
        if (message.isLocked)
          MessageLockedBody()
        // A panel replaces the body rather than sitting beside it: its text is
        // in its blocks, and rendering `text` as well would show whatever the
        // bot happened to leave in the column twice or not at all.
        else if (message.panel case final panel?)
          PanelView(
            panel: panel,

            onAction: widget.onPanelAction == null
                ? null
                : (action, value) =>
                      widget.onPanelAction!(message.id, action, value),
          )
        else if (_editing)
          MessageEditField(
            initialText: message.text,

            onSave: (text) {
              setState(() => _editing = false);
              if (text != message.text) widget.onEdit?.call(message.id, text);
            },
            onCancel: () => setState(() => _editing = false),
          )
        else ...[
          // Above the sender's own words, because it is what the message is
          // *about* — their line under it is a comment on it.
          if (message.forwarded case final forwarded?)
            MessageForwardedCard(
              forwarded: forwarded,
              attachmentLoader: widget.attachmentLoader,
            ),
          if (message.text.isNotEmpty)
            GuardedMessageText(
              messageId: message.id,
              text: message.text,
              child: MessageText(
                onSecondaryTap: _openContextMenu,
                span: TextSpan(
                  children: [
                    messageMarkupSpan(
                      message.text,
                      base: AppText.body.copyWith(
                        color: themeState.textSecondary,
                      ),
                      theme: themeState,
                      mentionable: widget.mentionable,
                      displayNames: widget.mentionNames,
                      onLink: _links.forUrl,
                    ),
                    if (message.isEdited)
                      TextSpan(
                        text: '  (edited)',
                        style: AppText.meta.copyWith(
                          color: themeState.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (message.attachments.isNotEmpty && widget.attachmentLoader != null)
          MessageAttachments(
            attachments: message.attachments,
            loader: widget.attachmentLoader!,
          ),
        if (message.preview case final preview? when preview.hasContent)
          LinkPreviewCard(preview: preview, loader: widget.attachmentLoader),
        if (showReactions)
          MessageReactionsBar(
            reactions: message.reactions,

            onToggle: _toggle,
            onAdd: _pickReaction,
          ),
      ],
    );
  }
}
