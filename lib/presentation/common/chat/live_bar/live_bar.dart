import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/classes/poll.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/live_items.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';
import 'widgets/live_polls_line.dart';
import 'widgets/live_polls_list.dart';

/// What is live in a channel, on top of its message box: the open polls,
/// which would otherwise scroll away up the chat while people are still meant
/// to vote in them.
///
/// Each kind is one line, folded by default. Only one is open at a time, and
/// an open one folds when the reader taps its top row or presses Escape —
/// never by itself, so picking in a multiple-choice poll does not shut it.
/// Draws nothing while nothing is live.
class LiveBar extends StatefulWidget {
  /// `ChannelChatState.live`: candidates, of which this draws what is open.
  final List<ChatMessage> live;
  final Map<String, PollTally> tallies;
  final void Function(String messageId, int option)? onVote;
  final void Function(String messageId)? onClosePoll;

  /// The clock, for tests. A poll leaves the bar when this passes its close.
  final DateTime Function() now;

  /// The most an opened line may take; past it, it scrolls inside itself.
  final double maxHeight;

  /// Around the bar when it is drawn, and not when it is not.
  final EdgeInsetsGeometry margin;

  const LiveBar({
    super.key,
    required this.live,
    required this.tallies,
    required this.onVote,
    required this.onClosePoll,
    this.now = DateTime.now,
    required this.maxHeight,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<LiveBar> createState() => _LiveBarState();
}

/// The line that can be open. One value per kind, so opening one is folding
/// the other.
enum _Line { polls }

class _LiveBarState extends State<LiveBar> {
  _Line? _open;

  /// Wakes the bar when the next poll closes, so it leaves with nothing else
  /// having changed.
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    // Not a focus shortcut: the chat unfocuses on every tap, and a key bound
    // to focus died after the first click anywhere.
    HardwareKeyboard.instance.addHandler(_onKey);
    _armCloseTimer();
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
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    setState(() => _open = null);
    return true;
  }

  void _toggle(_Line line) =>
      setState(() => _open = _open == line ? null : line);

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final now = widget.now();
    final polls = LiveItems.openPolls(widget.live, now);
    if (polls.isEmpty) return const SizedBox.shrink();
    final pollsOpen = _open == _Line.polls;

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
          LivePollsLine(
            polls: polls,
            tallies: widget.tallies,
            now: now,
            open: pollsOpen,
            onTap: () => _toggle(_Line.polls),
          ),
          AnimatedSize(
            duration: AppMotion.state,
            curve: AppMotion.settle,
            alignment: Alignment.topCenter,
            child: pollsOpen
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: widget.maxHeight),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: theme.borderPrimary),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: LivePollsList(
                          polls: polls,
                          tallies: widget.tallies,
                          onVote: widget.onVote,
                          onClosePoll: widget.onClosePoll,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
