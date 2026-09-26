import 'package:flutter/material.dart';

import '../../../../../data/classes/moderation_listing.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/item_card.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'moderation_listing_summary.dart';

/// A hidden listing, why and since when, and the way to put it back.
class HiddenListingCard extends StatelessWidget {
  final ModerationListing listing;
  final bool busy;
  final VoidCallback onShow;

  const HiddenListingCard({
    super.key,
    required this.listing,
    required this.busy,
    required this.onShow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final reason = listing.hiddenReason ?? '';
    final since = listing.hiddenAt;

    return ItemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ModerationListingSummary(listing: listing),
          const SizedBox(height: 10),
          Text(
            [
              if (since != null) 'Hidden ${HelperMethods.formatDate(since)}',
              reason.isEmpty ? 'No reason given' : reason,
            ].join(' · '),
            style: AppText.meta.copyWith(color: theme.textTertiary),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Show again',
            variant: AppButtonVariant.secondary,
            isLoading: busy,
            onPressed: busy ? null : onShow,
          ),
        ],
      ),
    );
  }
}
