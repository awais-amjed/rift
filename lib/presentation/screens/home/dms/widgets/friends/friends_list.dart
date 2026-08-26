import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/friend.dart';
import '../../../../../../data/enums/friendship_state.dart';
import '../../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../common/empty_state.dart';
import '../../../channels/channel_list/widgets/section_header.dart';
import '../../open_central_conversation.dart';
import 'friend_actions.dart';
import 'friend_row.dart';
import 'friends_tab_bar.dart';

/// The rows behind one tab of the friends page.
///
/// Pending is the only tab with two halves, and they are labelled rather than
/// merged: "wants to reach you" and "waiting for them" are opposite jobs, and
/// a single list of both would put an action you must take next to one you
/// can only wait on.
class FriendsList extends StatelessWidget {
  final FriendsTab tab;

  const FriendsList({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    final graph = context.watch<CentralDmCubit>().state.graph;

    return switch (tab) {
      FriendsTab.friends => _list(context, graph.friends),
      FriendsTab.blocked => _list(context, graph.blocked),
      FriendsTab.pending =>
        graph.incoming.isEmpty && graph.outgoing.isEmpty
            ? _empty()
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (graph.incoming.isNotEmpty) ...[
                    const SectionHeader(label: 'Wants to be friends'),
                    for (final friend in graph.incoming) _row(context, friend),
                  ],
                  if (graph.outgoing.isNotEmpty) ...[
                    const SectionHeader(label: 'Waiting for them'),
                    for (final friend in graph.outgoing) _row(context, friend),
                  ],
                ],
              ),
    };
  }

  Widget _list(BuildContext context, List<Friend> friends) {
    if (friends.isEmpty) return _empty();
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [for (final friend in friends) _row(context, friend)],
    );
  }

  Widget _row(BuildContext context, Friend friend) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: FriendRow(
        friend: friend,
        note: FriendActions.noteFor(friend.state),
        actions: FriendActions.forFriend(context, friend),
        // Somebody you have blocked leads nowhere. Everyone else does, an
        // unanswered request included: there is nothing new to read there, but
        // an older conversation with the same person might be worth re-reading
        // before deciding.
        onTap: friend.state == FriendshipState.blocked
            ? null
            : () => openCentralConversation(context, friend.toConversation()),
      ),
    );
  }

  /// Each tab is empty for a different reason, so each says its own thing.
  /// The friends one is the only one that asks for something, because it is
  /// the only tab you can put a row in directly — pending and blocked fill up
  /// as a side effect of what happens elsewhere.
  Widget _empty() => switch (tab) {
    FriendsTab.friends => const EmptyState(
      icon: Icons.person_add_alt_1_rounded,
      title: 'No friends yet',
      message:
          'Add someone by typing their full handle above. They have to accept '
          'before either of you can send anything.',
    ),
    FriendsTab.pending => const EmptyState(
      icon: Icons.hourglass_empty_rounded,
      title: 'Nothing pending',
      message:
          'Requests waiting on you, and the ones you are waiting on, both '
          'show up here.',
    ),
    FriendsTab.blocked => const EmptyState(
      icon: Icons.block_rounded,
      title: 'Nobody blocked',
      message:
          'Block someone and they land here. They cannot reach you or find '
          'you by handle until you undo it.',
    ),
  };
}
