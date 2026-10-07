part of 'chat_message_list.dart';

/// What one row is drawn from, apart from what every row shares. Two equal
/// inputs draw the same row.
typedef _RowInputs = ({
  ChatMessage message,
  bool showHeader,
  ChatMessage? repliedTo,
  ReplyOriginState originState,
  int? flashToken,
  bool animateIn,
  PollTally? pollTally,
});

/// Building a message's row, and not building it again when nothing it draws
/// has changed.
///
/// A chat screen rebuilds the list for every change to its conversation — an
/// upload's progress many times a second, one reaction, a message arriving —
/// and hands it new callbacks each time. Flutter skips a subtree only when it
/// is given the identical widget, so each row is kept with the inputs it was
/// built from and handed back as it is while they still hold: one message
/// changing rebuilds one row, not every row on screen.
///
/// The callbacks reach a row through this state, which reads the list's
/// current ones when called, so a kept row never acts with a stale one. A new
/// parameter on [ChatMessageRow] belongs in [_RowInputs] or [_sameForRows],
/// or a row keeps drawing its old value.
mixin _MessageListRowsMixin on State<ChatMessageList> {
  final Map<String, ({_RowInputs inputs, ChatMessageRow row})> _rows = {};

  /// The row for [rowId], kept from last time when [inputs] are unchanged.
  ChatMessageRow _keptRow(
    String rowId,
    _RowInputs inputs,
    ChatMessageRow Function() build,
  ) {
    final kept = _rows[rowId];
    if (kept != null && kept.inputs == inputs) return kept.row;
    final row = build();
    _rows[rowId] = (inputs: inputs, row: row);
    return row;
  }

  /// Drop kept rows the list no longer has, and all of them when something
  /// every row draws from has changed.
  void _refreshKeptRows(ChatMessageList old) {
    if (!_sameForRows(old, widget)) {
      _rows.clear();
    } else if (!identical(old.messages, widget.messages)) {
      final present = {for (final m in widget.messages) m.rowId};
      _rows.removeWhere((rowId, _) => !present.contains(rowId));
    }
  }

  /// A hot reload changes how rows are drawn without changing their inputs.
  @override
  void reassemble() {
    super.reassemble();
    _rows.clear();
  }

  /// Whether every row would be handed the same shared inputs. Callbacks are
  /// compared by whether there is one, since which one is read at call time.
  static bool _sameForRows(ChatMessageList a, ChatMessageList b) =>
      a.attachmentLoader == b.attachmentLoader &&
      a.isModerator == b.isModerator &&
      a.canReact == b.canReact &&
      setEquals(a.mentionable, b.mentionable) &&
      mapEquals(a.mentionNames, b.mentionNames) &&
      (a.onToggleReaction == null) == (b.onToggleReaction == null) &&
      (a.onOpenProfile == null) == (b.onOpenProfile == null) &&
      (a.onShowAround == null) == (b.onShowAround == null) &&
      (a.onReply == null) == (b.onReply == null) &&
      (a.onForward == null) == (b.onForward == null) &&
      (a.onEdit == null) == (b.onEdit == null) &&
      (a.onDelete == null) == (b.onDelete == null) &&
      (a.onRetry == null) == (b.onRetry == null) &&
      (a.onPanelAction == null) == (b.onPanelAction == null) &&
      (a.onTogglePin == null) == (b.onTogglePin == null) &&
      (a.onReport == null) == (b.onReport == null) &&
      (a.onVote == null) == (b.onVote == null) &&
      (a.onClosePoll == null) == (b.onClosePoll == null);

  // ── The list's current callbacks, read when called ───────────

  void _toggleReaction(String messageId, String emoji) =>
      widget.onToggleReaction?.call(messageId, emoji);
  void _reply(ChatMessage message) => widget.onReply?.call(message);
  void _forward(ChatMessage message) => widget.onForward?.call(message);
  void _edit(String messageId, String text) =>
      widget.onEdit?.call(messageId, text);
  void _delete(String messageId) => widget.onDelete?.call(messageId);
  void _retry(String pendingId) => widget.onRetry?.call(pendingId);
  void _panelAction(String messageId, String action, String? value) =>
      widget.onPanelAction?.call(messageId, action, value);
  void _togglePin(ChatMessage message) => widget.onTogglePin?.call(message);
  void _report(ChatMessage message) => widget.onReport?.call(message);
  void _vote(String messageId, int option) =>
      widget.onVote?.call(messageId, option);
  void _closePoll(String messageId) => widget.onClosePoll?.call(messageId);
}
