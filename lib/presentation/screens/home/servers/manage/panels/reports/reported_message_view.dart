import 'package:flutter/material.dart';

import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../../../logic/services/reported_message_opener.dart';
import '../../../../../../theme/app_text.dart';
import '../../../../../../theme/theme_context.dart';

/// The reported message, as this reviewer's device opened it.
///
/// Four outcomes and each says so, because a moderator deciding on a ban has
/// to know which of them they are looking at: the author's own words checked
/// against their signature, words sent in the clear, a key this device does
/// not hold, or a copy that does not carry the author's signature — which is
/// never shown, only said, like a forged message anywhere else.
class ReportedMessageView extends StatelessWidget {
  final ReportEntry entry;

  const ReportedMessageView({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final message = entry.message;
    final author =
        entry.report.target?.displayName ??
        entry.report.message?.originName ??
        'Somebody';
    final where = entry.report.channelName == null
        ? 'a channel you can\'t see'
        : '#${entry.report.channelName}';

    final (IconData icon, String caption) = switch (entry.content) {
      ReportedContent.verified => (
        Icons.verified_outlined,
        'Signed by $author · in $where',
      ),
      ReportedContent.plain => (
        Icons.lock_open_rounded,
        'Sent unencrypted · in $where',
      ),
      ReportedContent.locked => (
        Icons.lock_outline_rounded,
        'In $where. You don\'t hold its key, so you can\'t read it.',
      ),
      ReportedContent.unverified || null => (
        Icons.gpp_maybe_outlined,
        'This copy doesn\'t carry $author\'s signature, so it isn\'t shown.',
      ),
    };

    final attachments = message?.attachments.length ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          if (message != null && message.text.isNotEmpty)
            SelectableText(
              message.text,
              style: AppText.body.copyWith(color: theme.textPrimary),
            ),
          if (attachments > 0)
            Text(
              attachments == 1 ? '1 attachment' : '$attachments attachments',
              style: AppText.meta.copyWith(color: theme.textSecondary),
            ),
          Row(
            spacing: 6,
            children: [
              Icon(icon, size: K.iconInline, color: theme.textTertiary),
              Expanded(
                child: Text(
                  caption,
                  style: AppText.meta.copyWith(color: theme.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
