import 'package:flutter/material.dart';

import '../../../../../data/classes/public_bot.dart';
import '../../../../../data/constants.dart';
import '../../../../common/app_button.dart';
import '../../../../common/directory_icon.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../directory_moderation/listing_hidden_notice.dart';

/// One of your own listings, in [MyBotsModal].
///
/// Shows the like count because it is the only feedback the directory gives
/// an author — there are no installs to report, since adding a bot happens
/// entirely on somebody else's server and central never hears about it.
class MyBotRow extends StatelessWidget {
  final PublicBot bot;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const MyBotRow({
    super.key,
    required this.bot,
    required this.busy,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    final row = Row(
      spacing: 12,
      children: [
        DirectoryIcon(
          name: bot.name,
          seed: bot.id,
          iconPath: bot.iconPath,
          size: 36,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                bot.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.row.copyWith(color: theme.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (!bot.isListed) 'Hidden',
                  '${bot.likeCount} '
                      '${bot.likeCount == 1 ? 'like' : 'likes'}',
                  bot.sourceHost,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: theme.textTertiary,
                ),
              ),
            ],
          ),
        ),
        AppButton(
          label: 'Edit',
          variant: AppButtonVariant.secondary,
          onPressed: busy ? null : onEdit,
        ),
        AppButton(
          label: 'Withdraw',
          variant: AppButtonVariant.danger,
          onPressed: busy ? null : onRemove,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: bot.isHidden
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                row,
                ListingHiddenNotice(reason: bot.hiddenReason),
              ],
            )
          : row,
    );
  }
}
