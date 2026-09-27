import 'package:flutter/material.dart';

import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../../../logic/services/conversation_time.dart';
import '../../../../../../../logic/services/time_out_label.dart';
import '../../../../../../common/label_pill.dart';
import '../../../../../../theme/app_text.dart';
import '../../../../../../theme/theme_context.dart';
import 'report_actions.dart';
import 'reported_message_view.dart';

/// One report: why, about whom, from whom, the message if it was one, and —
/// while it is open — what can be done about it.
class ReportCard extends StatelessWidget {
  final ReportEntry entry;

  const ReportCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final report = entry.report;
    final target = report.target;
    final now = DateTime.now();
    final reporter = report.reporter?.displayName ?? 'A former member';
    final about =
        target?.displayName ?? report.message?.originName ?? 'Unknown';
    final until = target?.timedOutUntil;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgContent,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              LabelPill(label: report.reason.label),
              Expanded(
                child: Text(
                  report.message == null
                      ? '$about, reported by $reporter'
                      : 'Message from $about, reported by $reporter',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(color: theme.textPrimary),
                ),
              ),
              Text(
                formatMessageMoment(report.createdAt.toLocal(), now),
                style: AppText.meta.copyWith(color: theme.textTertiary),
              ),
            ],
          ),
          if (target != null && (target.isBanned || target.isTimedOut))
            Text(
              target.isBanned
                  ? '$about is banned.'
                  : '$about is timed out until ${timeOutEndLabel(until!)}.',
              style: AppText.meta.copyWith(color: theme.textSecondary),
            ),
          if (report.message != null) ReportedMessageView(entry: entry),
          if (report.note != null)
            Text(
              '“${report.note}”',
              style: AppText.secondary.copyWith(color: theme.textSecondary),
            ),
          if (report.isOpen)
            ReportActions(entry: entry)
          else
            Text(
              'Closed · ${report.outcome!.label}'
              '${report.resolvedAt == null ? '' : ' · ${formatMessageMoment(report.resolvedAt!.toLocal(), now)}'}',
              style: AppText.meta.copyWith(color: theme.textTertiary),
            ),
        ],
      ),
    );
  }
}
