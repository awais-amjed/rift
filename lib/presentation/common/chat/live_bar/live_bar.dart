import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/classes/poll.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/attachment_loader.dart';
import '../../../../logic/services/live_items.dart';
import '../../../../logic/services/panel_summary.dart';
import '../../../../logic/services/poll_ops.dart';
import '../../../theme/theme_context.dart';
import '../panel/panel_actions.dart';
import '../panel/panel_view.dart';
import 'widgets/live_bar_opened.dart';
import 'widgets/live_panel_line.dart';
import 'widgets/live_polls_line.dart';
import 'widgets/live_polls_list.dart';

/// What is live in a channel, on top of its message box: a bot's player and
/// the open polls, which would otherwise scroll away up the chat.
///
/// One line per live panel, then one for the polls, each folded by default.
/// Only one is open at a time, and an open one folds when the reader taps its
/// top row or presses Escape — never by itself, so picking in a
/// multiple-choice poll does not shut it. Draws nothing while nothing is live.
class LiveBar extends StatefulWidget {
  /// `ChannelChatState.live`: candidates, of which this draws the open polls.
  final List<ChatMessage> live;

  /// The live panels to draw, already decided (`LiveItems.shownPanels`).
  final List<ChatMessage> panels;

  final Map<String, PollTally> tallies;
  final void Function(String messageId, int option)? onVote;
  final void Function(String messageId)? onClosePoll;
  final void Function(String messageId, String action, String? value)?
  onPanelAction;

  /// The chat's own, for a panel's pictures.
  final AttachmentLoader? loader;

  /// The clock, for tests. A poll leaves the bar when this passes its close.
  final DateTime Function() now;

  /// The most an opened line may take; past it, it scrolls inside itself.
  final double maxHeight;

  /// Around the bar when it is drawn, and not when it is not.
  final EdgeInsetsGeometry margin;

  const LiveBar({
    super.key,
    required this.live,
    this.panels = const [],
    required this.tallies,
    required this.onVote,
    required this.onClosePoll,
    this.onPanelAction,
    this.loader,
    this.now = DateTime.now,
    required this.maxHeight,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<LiveBar> createState() => _LiveBarState();
}

/// [_LiveBarState._open] for the polls line; a panel's line is its message id.
const _pollsLine = 'polls';

class _LiveBarState extends State<LiveBar> {
  /// The open line, or null with all of them folded.
  String? _open;

  /// The page the bar is on. Escape is the bar's only while that page is on
  /// top: a dialog over it closes on Escape, as it always has.
  ModalRoute<Object?>? _route;

  /// Wakes the bar when the next poll closes, so it leaves with nothing else
  /// having changed.
  Timer? _closeTimer;

  /// The polls section as last built, and what it was built from. A player
  /// redraws every few seconds; handing back the same widget when the polls
  /// have not changed keeps that from rebuilding them.
  List<ChatMessage> _polls = const [];
  Object? _pollsInputs;
  Widget? _pollsSection;

  @override
  void initState() {
    super.initState();
    // Not a focus shortcut: the chat unfocuses on every tap, and a key bound
    // to focus died after the first click anywhere.
    HardwareKeyboard.instance.addHandler(_onKey);
    _armCloseTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(LiveBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.live, widget.live)) _armCloseTimer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _closeTimer?.cancel();
    super.dispose();
  }

  void _armCloseTimer() {
    _closeTimer?.cancel();
    final now = widget.now();
    final next = LiveItems.nextClose(
      LiveItems.openPolls(widget.live, now),
      now,
    );
    if (next == null) return;
    _closeTimer = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _armCloseTimer();
    });
  }

  bool _onKey(KeyEvent event) {
    if (_open == null ||
        !(_route?.isCurrent ?? true) ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    setState(() => _open = null);
    return true;
  }

  void _toggle(String line) =>
      setState(() => _open = _open == line ? null : line);

  /// The open polls, as the same list while they say the same.
  List<ChatMessage> _openPolls(DateTime now) {
    final polls = LiveItems.openPolls(widget.live, now);
    if (!listEquals(polls, _polls)) _polls = polls;
    return _polls;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final now = widget.now();
    final polls = _openPolls(now);
    final panels = widget.panels;
    if (polls.isEmpty && panels.isEmpty) return const SizedBox.shrink();
    // A line that went away while open: none is open now.
    final open = _open == _pollsLine
        ? (polls.isEmpty ? null : _pollsLine)
        : panels.any((p) => p.id == _open)
        ? _open
        : null;

    final hairline = Divider(height: 1, color: theme.borderPrimary);
    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: theme.bgElevated,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderPrimary),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, message) in panels.indexed) ...[
            if (i > 0) hairline,
            ..._panel(message, open: open == message.id),
          ],
          if (polls.isNotEmpty) ...[
            if (panels.isNotEmpty) hairline,
            _pollsSectionFor(polls, now, open: open == _pollsLine),
          ],
        ],
      ),
    );
  }

  List<Widget> _panel(ChatMessage message, {required bool open}) {
    final onPanelAction = widget.onPanelAction;
    final onAction = onPanelAction == null
        ? null
        : (String action, String? value) =>
              onPanelAction(message.id, action, value);
    final (body, controls) = PanelSummary.pinControls(message.panel!);
    return [
      LivePanelLine(
        summary: PanelSummary.of(message.panel!),
        botName: message.authorName,
        open: open,
        onTap: () => _toggle(message.id),
        onAction: onAction,
        loader: widget.loader,
      ),
      LiveBarOpened(
        open: open,
        maxHeight: widget.maxHeight,
        footer: controls.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final block in controls)
                    PanelActions(block: block, onAction: onAction),
                ],
              ),
        child: PanelView(
          panel: body,
          onAction: onAction,
          loader: widget.loader,
        ),
      ),
    ];
  }

  Widget _pollsSectionFor(
    List<ChatMessage> polls,
    DateTime now, {
    required bool open,
  }) {
    final inputs = (
      polls,
      widget.tallies,
      open,
      // The only thing the clock changes on the folded line.
      PollOps.timeLeft(polls.first.poll!.closesAt, now),
      widget.onVote,
      widget.onClosePoll,
      widget.maxHeight,
    );
    if (inputs == _pollsInputs && _pollsSection != null) return _pollsSection!;
    _pollsInputs = inputs;
    return _pollsSection = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LivePollsLine(
          polls: polls,
          tallies: widget.tallies,
          now: now,
          open: open,
          onTap: () => _toggle(_pollsLine),
        ),
        LiveBarOpened(
          open: open,
          maxHeight: widget.maxHeight,
          child: LivePollsList(
            polls: polls,
            tallies: widget.tallies,
            onVote: widget.onVote,
            onClosePoll: widget.onClosePoll,
          ),
        ),
      ],
    );
  }
}
