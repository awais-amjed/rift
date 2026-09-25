import 'package:flutter/material.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';

/// Sits above the composer while what is typed will be sent **in the clear**.
///
/// The whole reason it exists is timing. Everything else in this design says
/// "this message was not encrypted" — the badge does, the tooltip does — and
/// all of it arrives after the fact. This is the one that arrives while there
/// is still a decision to make.
///
/// BOTS.md §4: `/roll 2d6` in the clear is nothing. Somebody typing `/ask` and
/// pasting something personal into an AI bot is a different event, and they
/// need to know while they can still stop.
///
/// It names the bot, because "this is unencrypted" is only half the sentence —
/// *who gets to read it* is the half people actually weigh.
class ComposerPlaintextNotice extends StatelessWidget {
  final ServerMember bot;
  const ComposerPlaintextNotice({super.key, required this.bot});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final dataUse = bot.manifest.dataUse;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: CustomColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: CustomColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Icon(
            Icons.lock_open_rounded,
            size: 14,
            color: context.theme.statusInk(CustomColors.warning),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  'Sent to ${bot.displayName} without encryption — the server '
                  'and everyone here can read it.',
                  style: AppText.meta.copyWith(color: themeState.textSecondary),
                ),
                // The bot's own words about what it does with what it is
                // handed (BOTS.md §8). Worth more than any amount of key
                // management for an AI bot: it reads the command either way,
                // and this is the moment that matters.
                if (dataUse != null)
                  Text(
                    dataUse,
                    style: AppText.meta.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
