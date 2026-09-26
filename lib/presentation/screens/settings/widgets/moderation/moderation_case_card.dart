import 'package:flutter/material.dart';

import '../../../../../data/classes/moderation_case.dart';
import '../../../../common/app_button.dart';
import '../../../../common/item_card.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'listing_report_row.dart';
import 'moderation_listing_summary.dart';

/// One listing in the queue, its reports, and the three things a moderator
/// can do about it.
class ModerationCaseCard extends StatelessWidget {
  final ModerationCase item;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback onDismiss;

  /// Null once the publisher is banned already.
  final VoidCallback? onBan;

  const ModerationCaseCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onHide,
    required this.onDismiss,
    this.onBan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final count = item.reports.length;
    final first = item.reports.isEmpty ? null : item.reports.last;

    return ItemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ModerationListingSummary(listing: item.listing),
          // What the reporters saw, when the owner has changed it since: a
          // listing edited clean is still worth knowing about.
          if (item.editedSinceReport && first != null) ...[
            const SizedBox(height: 10),
            Text(
              'Changed since it was reported. It said: '
              '"${first.reportedName ?? ''}"'
              '${(first.reportedDescription ?? '').isEmpty ? '' : ' — "${first.reportedDescription}"'}',
              style: AppText.meta.copyWith(color: theme.textTertiary),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            count == 1 ? '1 REPORT' : '$count REPORTS',
            style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
          ),
          const SizedBox(height: 6),
          for (final report in item.reports) ...[
            ListingReportRow(report: report),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'Hide…',
                variant: AppButtonVariant.danger,
                onPressed: busy ? null : onHide,
              ),
              AppButton(
                label: 'Keep it up',
                variant: AppButtonVariant.secondary,
                isLoading: busy,
                onPressed: busy ? null : onDismiss,
              ),
              if (onBan != null)
                AppButton(
                  label: 'Ban publisher…',
                  variant: AppButtonVariant.secondary,
                  onPressed: busy ? null : onBan,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
