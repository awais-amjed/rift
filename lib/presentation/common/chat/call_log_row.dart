import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/classes/dm_call.dart';
import '../../../data/constants.dart';
import '../../../logic/services/call_log_label.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';

/// A call in the conversation it happened in: one quiet line between the
/// messages, at the time it rang. A missed call is the one drawn in red,
/// because it is the one that asks something of the reader.
class CallLogRow extends StatelessWidget {
  final DmCall call;
  final String myId;

  const CallLogRow({super.key, required this.call, required this.myId});

  @override
  Widget build(BuildContext context) {
    final label = CallLogLabel.of(call, myId: myId);
    if (label == null) return const SizedBox.shrink();
    final theme = context.theme;
    final missedHere =
        label.kind == CallLogKind.missed && call.isIncomingFor(myId);
    final icon = switch (label.kind) {
      CallLogKind.answered => Icons.call_rounded,
      CallLogKind.ongoing => Icons.phone_in_talk_rounded,
      CallLogKind.missed => Icons.phone_missed_rounded,
      CallLogKind.declined => Icons.call_end_rounded,
    };
    final tint = missedHere
        ? theme.statusInk(CustomColors.error)
        : theme.textTertiary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        spacing: 8,
        children: [
          Icon(icon, size: K.iconRow, color: tint),
          Flexible(
            child: Text(
              label.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.secondary.copyWith(
                color: missedHere ? tint : theme.textSecondary,
              ),
            ),
          ),
          Text(
            DateFormat.jm().format(call.startedAt.toLocal()),
            style: AppText.meta.copyWith(color: theme.textTertiary),
          ),
        ],
      ),
    );
  }
}
