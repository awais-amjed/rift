import 'package:flutter/material.dart';

import '../../../../../data/classes/chat_message.dart';
import '../../../../../data/classes/poll.dart';
import '../../../../../logic/services/poll_ops.dart';
import 'live_bar_line.dart';

/// The polls line, folded: the newest open poll, how it stands, and how many
/// more are open. Opened, it only names how many there are — the list under
/// it says the rest.
class LivePollsLine extends StatelessWidget {
  /// Open polls, newest first. Never empty.
  final List<ChatMessage> polls;
  final Map<String, PollTally> tallies;
  final DateTime now;
  final bool open;
  final VoidCallback onTap;

  const LivePollsLine({
    super.key,
    required this.polls,
    required this.tallies,
    required this.now,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final newest = polls.first;
    final poll = newest.poll!;
    final voters = tallies[newest.id]?.voters ?? 0;
    final votes = voters == 1 ? '1 vote' : '$voters votes';
    return LiveBarLine(
      icon: Icons.poll_outlined,
      title: open
          ? (polls.length == 1 ? '1 open poll' : '${polls.length} open polls')
          : poll.question,
      meta: open ? null : '$votes · ${PollOps.timeLeft(poll.closesAt, now)}',
      trailing: !open && polls.length > 1 ? '+${polls.length - 1} more' : null,
      open: open,
      onTap: onTap,
    );
  }
}
