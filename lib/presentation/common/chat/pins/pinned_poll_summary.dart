import 'package:flutter/material.dart';

import '../../../../data/classes/poll.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/poll_ops.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// A pinned poll, as the pinned list shows it: the question and whether it is
/// still open. No options and no results — those are the poll's own card, one
/// press away, and a second copy here would be a second thing to keep live.
class PinnedPollSummary extends StatelessWidget {
  final Poll poll;

  const PinnedPollSummary({super.key, required this.poll});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final options = poll.options.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: themeState.borderPrimary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.poll_outlined,
              size: K.iconRow,
              color: themeState.textTertiary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  poll.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.strong.copyWith(color: themeState.textPrimary),
                ),
                Text(
                  '$options options · '
                  '${PollOps.timeLeft(poll.closesAt, DateTime.now())}',
                  style: AppText.meta.copyWith(color: themeState.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
