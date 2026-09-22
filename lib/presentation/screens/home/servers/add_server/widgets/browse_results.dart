import 'package:flutter/material.dart';

import '../../../../../../data/classes/public_server.dart';
import '../../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/empty_state.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/list_loading_footer.dart';
import '../../../../../common/loading_block.dart';
import 'public_server_tile.dart';

/// What the browser shows where the results go: the list, or the reason there
/// isn't one.
///
/// The four states are kept apart deliberately. "Nothing matches your search"
/// and "the directory is empty" look identical if you only count rows, and
/// they call for completely different things — one is a hint to search for
/// less, the other is a hint that this is a young directory and creating a
/// server is the way in.
class BrowseResults extends StatelessWidget {
  final PublicServersState state;
  final Set<String> joinedServerIds;
  final void Function(PublicServer server) onJoin;
  final VoidCallback onRetry;

  /// Asked for when the list is scrolled near its end. Safe to fire often —
  /// [PublicServersCubit.loadMore] drops a call made while one is in flight or
  /// after the end.
  final VoidCallback onLoadMore;

  const BrowseResults({
    super.key,
    required this.state,
    required this.joinedServerIds,
    required this.onJoin,
    required this.onRetry,
    required this.onLoadMore,
  });

  /// How close to the bottom counts as "nearly there" — about two tiles.
  static const double _loadMoreSlack = 200;

  @override
  Widget build(BuildContext context) {
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HintCard(
              icon: Icons.cloud_off_outlined,
              text: state.error!,
              action: AppButton(
                label: 'Try again',
                variant: AppButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      );
    }

    // Only on the first load. A search that is still running keeps the
    // previous results on screen rather than blinking to a spinner per
    // keystroke.
    if (state.loading && !state.hasBrowsed) {
      return const LoadingBlock();
    }

    if (state.results.isEmpty) {
      final searching = state.query.trim().isNotEmpty || state.tag != null;
      // The same treatment the friends tabs use: a list body with nothing in
      // it keeps its own background, rather than growing a card in the middle.
      return EmptyState(
        icon: searching ? Icons.search_off_outlined : Icons.public_outlined,
        title: searching ? 'No matches' : 'Nothing listed yet',
        message: searching
            ? 'Try fewer words, or clear the tag.'
            : 'Create a server and list it under Discovery in its settings, '
                  'and it shows up here.',
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
          if (index == state.results.length) return const ListLoadingFooter();
          final server = state.results[index];
          return PublicServerTile(
            server: server,
            onJoin: joinedServerIds.contains(server.serverId)
                ? null
                : () => onJoin(server),
          );
        },
      ),
    );
  }
}
