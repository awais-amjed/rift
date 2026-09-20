import 'package:flutter/material.dart';

import '../../../../../data/classes/public_bot.dart';
import '../../../../../logic/cubits/public_bots/public_bots_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/empty_state.dart';
import '../../../../common/hint_card.dart';
import 'public_bot_tile.dart';

/// What the bot browser shows where the results go: the list, or the reason
/// there isn't one.
///
/// The same four states the server browser keeps apart, for the same reason —
/// "nothing matches your search" and "the directory is empty" look identical
/// if you only count rows, and one is a hint to search for less while the
/// other is a hint that nobody has listed a bot yet.
class BotResults extends StatelessWidget {
  final PublicBotsState state;

  /// Null when this client has no server it may add a bot to. Passed down
  /// rather than decided per row: it is a fact about the client, not the bot.
  final void Function(PublicBot bot)? onAdd;

  final void Function(PublicBot bot)? onLike;
  final void Function(PublicBot bot) onOpenSource;
  final VoidCallback onRetry;

  /// Asked for when the list is scrolled near its end. Safe to fire often —
  /// [PublicBotsCubit.loadMore] drops a call made while one is in flight or
  /// after the end.
  final VoidCallback onLoadMore;

  const BotResults({
    super.key,
    required this.state,
    required this.onAdd,
    required this.onLike,
    required this.onOpenSource,
    required this.onRetry,
    required this.onLoadMore,
  });

  /// How close to the bottom counts as "nearly there" — about two tiles.
  static const double _loadMoreSlack = 200;

  @override
  Widget build(BuildContext context) {
    if (state.error != null) {
      return Center(
        child: HintCard(
          icon: Icons.cloud_off_outlined,
          text: state.error!,
          action: AppButton(
            label: 'Try again',
            variant: AppButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ),
      );
    }

    // Only on the first load. A search that is still running keeps the
    // previous results on screen rather than blinking to a spinner per
    // keystroke.
    if (state.loading && !state.hasBrowsed) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (state.results.isEmpty) {
      final searching = state.query.trim().isNotEmpty || state.tag != null;
      return EmptyState(
        icon: searching ? Icons.search_off_outlined : Icons.smart_toy_outlined,
        title: searching ? 'No matches' : 'No bots listed yet',
        message: searching
            ? 'Try fewer words, or clear the tag.'
            : 'Write one with the bot SDK and list it here, and anybody '
                  'running a Rift server can find it.',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (state.hasMore &&
            notification.metrics.extentAfter < _loadMoreSlack) {
          onLoadMore();
        }
        // Never swallowed — the scrollbar is still listening.
        return false;
      },
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: state.results.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == state.results.length) return _buildFooter();
          final bot = state.results[index];
          return PublicBotTile(
            bot: bot,
            onAdd: onAdd == null ? null : () => onAdd!(bot),
            onLike: onLike == null ? null : () => onLike!(bot),
            likeBusy: state.liking.contains(bot.id),
            onOpenSource: () => onOpenSource(bot),
          );
        },
      ),
    );
  }

  /// The spinner at the end of a page, which is also what tells somebody the
  /// directory has not simply stopped at fifty.
  Widget _buildFooter() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
