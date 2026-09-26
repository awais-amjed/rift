import 'package:flutter/material.dart';

import '../../../../../data/classes/listing_report.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One report under a listing in the queue: why, in the reporter's words if
/// they gave any, by whom and when.
class ListingReportRow extends StatelessWidget {
  final ListingReport report;

  const ListingReportRow({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final details = report.details;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: report.reason.label,
                style: AppText.label.copyWith(color: theme.textPrimary),
              ),
              TextSpan(
                text:
                    '  @${report.reporterHandle} · '
                    '${HelperMethods.formatDateTime(report.createdAt)}',
                style: AppText.meta.copyWith(color: theme.textTertiary),
              ),
            ],
          ),
        ),
        if (details != null && details.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            details,
            style: AppText.secondary.copyWith(color: theme.textSecondary),
          ),
        ],
      ],
    );
  }
}
