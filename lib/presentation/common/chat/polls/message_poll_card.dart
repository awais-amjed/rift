import 'package:flutter/material.dart';

import '../../../../data/classes/poll.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/poll_ops.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../link_preview_card.dart';
import 'poll_option_row.dart';

/// A poll inside a message: the question, its options, and how it stands.
///
/// **Results show once you have voted, or once it has ended** — before that
/// the bars would be the thing people vote *with*. Counts only, always: who
/// voted for what is not something any member can see (`poll_tallies`).
///
/// The same bounded card as a link preview or a bot's panel, because it is
/// the same kind of thing: a card inside a message, not the message's width.
class MessagePollCard extends StatelessWidget {
  final Poll poll;

  /// How it stands, or null until the counts have arrived.
  final PollTally? tally;

  /// Whether the reader posted it — the one person who may end it early.
  final bool isMine;

  /// Tap an option. Null where voting is not possible from here.
  final ValueChanged<int>? onVote;

  /// End the poll now. Null unless [isMine] and it is still open.
  final VoidCallback? onClose;

  const MessagePollCard({
    super.key,
    required this.poll,
    required this.tally,
    required this.isMine,
    this.onVote,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final now = DateTime.now();
    final closed = poll.isClosedAt(now);
    final tally = this.tally ?? PollTally.empty(poll.options.length);
    final showResults = closed || tally.mine.isNotEmpty;
    final voters = tally.voters == 1 ? '1 vote' : '${tally.voters} votes';

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LinkPreviewCard.maxWidth),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: themeState.bgSecondary,
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                poll.question,
                style: AppText.row.copyWith(
                  color: themeState.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                closed
                    ? 'Final results'
                    : poll.multiple
                    ? 'Pick one or more'
                    : 'Pick one',
                style: AppText.meta.copyWith(color: themeState.textTertiary),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < poll.options.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                PollOptionRow(
                  label: poll.options[i],
                  picked: tally.mine.contains(i),
                  multiple: poll.multiple,
                  share: showResults ? tally.shareOf(i) : null,
                  onTap: closed || onVote == null ? null : () => onVote!(i),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                spacing: 6,
                children: [
                  Text(
                    '$voters · ${PollOps.timeLeft(poll.closesAt, now)}',
                    style: AppText.meta.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  if (isMine && !closed && onClose != null)
                    _EndPollLink(onTap: onClose!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "End poll", as a quiet link rather than a button: it is the author's, it
/// is rare, and a button in every poll card would be the loudest thing in it.
class _EndPollLink extends StatelessWidget {
  final VoidCallback onTap;

  const _EndPollLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          'End poll',
          style: AppText.meta.copyWith(
            color: themeState.accentBright,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
