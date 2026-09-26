import 'package:flutter/material.dart';

import '../../../../../data/classes/moderation_listing.dart';
import '../../../../../data/enums/listing_kind.dart';
import '../../../../common/directory_icon.dart';
import '../../../../common/label_pill.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// What a moderator needs to recognise a listing: its icon and name, which
/// directory it is in, where it points, and who published it.
class ModerationListingSummary extends StatelessWidget {
  final ModerationListing listing;

  const ModerationListingSummary({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final description = listing.description;
    final meta = AppText.label.copyWith(
      fontWeight: FontWeight.w400,
      color: theme.textTertiary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        DirectoryIcon(
          name: listing.name,
          seed: listing.seed,
          iconPath: listing.iconPath,
          size: 40,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: Text(
                      listing.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.row.copyWith(color: theme.textPrimary),
                    ),
                  ),
                  LabelPill(
                    label: listing.kind == ListingKind.server
                        ? 'SERVER'
                        : 'BOT',
                  ),
                  if (!listing.isListed) const LabelPill(label: 'UNLISTED'),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${listing.host} · by @${listing.ownerHandle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
              if (listing.ownerBanned) ...[
                const SizedBox(height: 4),
                LabelPill(
                  label: 'PUBLISHER BANNED',
                  color: theme.statusInk(CustomColors.error),
                ),
              ],
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: AppText.secondary.copyWith(color: theme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
