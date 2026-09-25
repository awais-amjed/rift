part of 'chat_message_row.dart';

/// What can be done to a message, and doing it: the checks behind each
/// action, the desktop context menu, the phone's action sheet, and the copy
/// and delete they both end in.
///
/// Split out because none of it draws the row. It decides what the menus
/// offer and answers what was picked; the row only says where the pointer is.
mixin _MessageRowActionsMixin on State<ChatMessageRow> {
  /// Implemented by the State class.
  ChatMessage get message;
  ThemeState get themeState;
  void _startEditing();

  /// Whether a reaction could be shown at all — the surface supports them and
  /// this message is one that can carry one. Separate from [_canReact], which
  /// also asks whether this member may add their own.
  bool get _canReactAtAll =>
      widget.onToggleReaction != null &&
      !message.isPending &&
      // Reacting to a message you cannot read is a mis-click waiting to
      // happen, and the tally would be visible to everyone who can.
      !message.isLocked;

  bool get _canReact => _canReactAtAll && widget.canReact;
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
  bool get _canPin =>
      widget.onTogglePin != null && MessagePermissions.canPin(message);
  bool get _canDelete =>
      widget.onDelete != null &&
      MessagePermissions.canDelete(message, isModerator: widget.isModerator);

  void _toggle(String emoji) =>
      widget.onToggleReaction?.call(message.id, emoji);

  void _reply() => widget.onReply?.call(message);

  void _togglePin() => widget.onTogglePin?.call(message);

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
      canPin: _canPin,
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
      case MessageMenuAction.pin:
        _togglePin();
      case MessageMenuAction.edit:
        _startEditing();
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
      canPin: _canPin,
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
      case MenuActionChoice(action: MessageMenuAction.pin):
        _togglePin();
      case MenuActionChoice(action: MessageMenuAction.edit):
        _startEditing();
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

  /// Ending a poll early cannot be taken back, and it ends it for everyone.
  Future<void> _confirmClosePoll() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'End this poll?',
      message: 'Voting stops now for everyone, and the results are final.',
      confirmLabel: 'End poll',
      icon: Icons.poll_outlined,
    );
    if (confirmed) widget.onClosePoll?.call(message.id);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: message.text));
    HelperMethods.showToast(title: 'Copied', description: 'Message copied.');
  }
}
