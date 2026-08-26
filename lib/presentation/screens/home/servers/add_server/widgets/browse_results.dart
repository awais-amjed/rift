import 'package:flutter/material.dart';

import '../../../../../../data/classes/public_server.dart';
import '../../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/empty_state.dart';
import '../../../../../common/hint_card.dart';
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

  const BrowseResults({
    super.key,
    required this.state,
    required this.joinedServerIds,
    required this.onJoin,
    required this.onRetry,
  });

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
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
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

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: state.results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final server = state.results[index];
        return PublicServerTile(
          server: server,
          onJoin: joinedServerIds.contains(server.serverId)
              ? null
              : () => onJoin(server),
        );
      },
    );
  }
}
