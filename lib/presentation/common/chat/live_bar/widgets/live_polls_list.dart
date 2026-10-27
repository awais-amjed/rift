import 'package:flutter/material.dart';

import '../../../../../data/classes/chat_message.dart';
import '../../../../../data/classes/poll.dart';
import '../../../../theme/theme_context.dart';
import '../../polls/message_poll_card.dart';

/// Every open poll in the channel, opened in the bar: each drawn as the chat
/// draws it, and voted in right there.
class LivePollsList extends StatelessWidget {
  /// Open polls, newest first.
  final List<ChatMessage> polls;
  final Map<String, PollTally> tallies;

  /// Null where the reader cannot vote — the same rule as the history's.
  final void Function(String messageId, int option)? onVote;
  final void Function(String messageId)? onClosePoll;

  const LivePollsList({
    super.key,
    required this.polls,
    required this.tallies,
    required this.onVote,
    required this.onClosePoll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, message) in polls.indexed) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: theme.borderPrimary),
            ),
          MessagePollCard(
            poll: message.poll!,
            tally: tallies[message.id],
            isMine: message.isMine,
            onVote: onVote == null
                ? null
                : (option) => onVote!(message.id, option),
            onClose: message.isMine && onClosePoll != null
                ? () => onClosePoll!(message.id)
                : null,
          ),
        ],
      ],
    );
  }
}
