import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/public_bot.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/public_bots/public_bots_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/directory_icon.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../directory_reports/report_listing_button.dart';
import 'bot_command_list.dart';
import 'bot_like_button.dart';
import 'bot_source_link.dart';

/// One bot in the browser.
///
/// The source host sits where a server row puts the Supabase host, and for
/// the same reason: it is the only claim on the row that can be checked. A
/// server listing at least points at a running database; a bot listing points
/// at nothing until somebody runs it, so "where is the code" is the whole of
/// what a stranger has to go on.
class PublicBotTile extends StatelessWidget {
  final PublicBot bot;

  /// Opens the pick-a-server step. Null when this client has no server it may
  /// add a bot to, in which case the row says so rather than offering a
  /// button that leads to an empty list.
  final VoidCallback? onAdd;

  /// Null when signed out of the central account — the count still shows.
  final VoidCallback? onLike;

  final bool likeBusy;

  /// Opens [bot]'s source in a browser.
  final VoidCallback? onOpenSource;

  const PublicBotTile({
    super.key,
    required this.bot,
    this.onAdd,
    this.onLike,
    this.likeBusy = false,
    this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          DirectoryIcon(
            name: bot.name,
            seed: bot.id,
            iconPath: bot.iconPath,
            size: 40,
          ),
          Expanded(child: _details(context)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (onAdd != null)
                AppButton(label: 'Add', onPressed: onAdd)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    'No server',
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.textTertiary,
                    ),
                  ),
                ),
              BotLikeButton(
                count: bot.likeCount,
                liked: bot.likedByMe,
                busy: likeBusy,
                onTap: onLike,
              ),
            ],
          ),
          if (bot.ownerId != context.read<PublicBotsCubit>().currentUserId)
            ReportListingButton(
              name: bot.name,
              onReport: (reason, details) => context
                  .read<PublicBotsCubit>()
                  .report(bot.id, reason, details),
            ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    final theme = context.theme;
    final description = bot.description;

    return Column(
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
        // A link, not a caption: the whole of "should I run this" is behind
        // it, and a row that only names the host makes somebody go and look
        // the bot up by hand.
        BotSourceLink(host: bot.sourceHost, onTap: onOpenSource),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.secondary.copyWith(color: theme.textSecondary),
          ),
        ],
        BotCommandList(manifest: bot.manifest),
        if (bot.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final tag in bot.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.bgTertiary,
                    borderRadius: BorderRadius.circular(K.radiusPill),
                  ),
                  child: Text(
                    tag,
                    style: AppText.label.copyWith(color: theme.textTertiary),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
