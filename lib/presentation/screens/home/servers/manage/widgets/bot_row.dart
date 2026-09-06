import 'package:flutter/material.dart';

import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/constants.dart';
import '../../../../../common/label_pill.dart';
import '../../../../../common/squircle_avatar.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// One bot on the bots page: who it is, and the way into what it can reach.
class BotRow extends StatelessWidget {
  final ServerMember bot;
  final VoidCallback onTap;

  const BotRow({super.key, required this.bot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          spacing: 10,
          children: [
            SquircleAvatar(name: bot.displayName, seed: bot.id, size: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bot.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(color: themeState.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${bot.username}',
                    style: AppText.secondary.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (bot.isBanned)
              const LabelPill(label: 'Banned', color: CustomColors.error),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: themeState.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
