import 'package:flutter/material.dart';

import '../../../../../data/classes/publisher_ban.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/item_card.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// An account that may not publish, and the way to let it again.
class PublisherBanRow extends StatelessWidget {
  final PublisherBan ban;
  final bool busy;
  final VoidCallback onLift;

  const PublisherBanRow({
    super.key,
    required this.ban,
    required this.busy,
    required this.onLift,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final reason = ban.reason ?? '';
    final by = ban.bannedByHandle;

    return ItemCard(
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '@${ban.handle}',
                  style: AppText.row.copyWith(color: theme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    HelperMethods.formatDate(ban.createdAt),
                    if (by != null) 'by @$by',
                    reason.isEmpty ? 'No reason given' : reason,
                  ].join(' · '),
                  style: AppText.meta.copyWith(color: theme.textTertiary),
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Lift ban',
            variant: AppButtonVariant.secondary,
            isLoading: busy,
            onPressed: busy ? null : onLift,
          ),
        ],
      ),
    );
  }
}
