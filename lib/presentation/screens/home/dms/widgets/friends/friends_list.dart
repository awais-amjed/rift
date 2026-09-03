import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/friend.dart';
import '../../../../../../data/classes/friend_buckets.dart';
import '../../../../../../data/classes/paged.dart';
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
/// can only wait on. They are two buckets on the wire for the same reason.
///
/// **The rows arrive when the tab is opened** (central migration 014), and
/// page as it is scrolled. Nothing outside a tab reads its rows any more — the
/// badge and the tab labels come from `friend_counts`, and a conversation's
/// state rides on the conversation row — so there is nothing left that needed
/// them eagerly.
///
/// Built lazily too. It used to be `ListView(children: […])`, which builds
/// every row whether or not it is on screen; a paged list that did that would
/// be paging rows in only to construct them all over again.
class FriendsList extends StatelessWidget {
  final FriendsTab tab;

  const FriendsList({super.key, required this.tab});

  /// How close to the bottom counts as "nearly there" — about three rows.
  static const double _loadMoreSlack = 180;

  /// The buckets this tab draws, in the order it draws them. Pending is the
  /// only tab that shows two, each under its own heading.
  List<FriendBucket> get _buckets => switch (tab) {
    FriendsTab.friends => const [FriendBucket.friends],
    FriendsTab.blocked => const [FriendBucket.blocked],
    FriendsTab.pending => const [FriendBucket.incoming, FriendBucket.outgoing],
  };

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<CentralDmCubit>();
    final buckets = cubit.state.friends;
    final pages = [for (final bucket in _buckets) buckets.pageOf(bucket)];

    // Null is "not fetched yet", which is not the same as "nobody is here" —
    // saying the latter while the first page is in flight tells somebody
    // something untrue about their own account.
    if (pages.any((page) => page == null)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (pages.every((page) => page!.isEmpty)) return _empty();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter >= _loadMoreSlack) return false;
        for (final bucket in _buckets) {
          if (buckets.pageOf(bucket)?.hasMore ?? false) {
            unawaited(cubit.loadMoreFriends(bucket));
          }
        }
        return false;
      },
      child: _list(context, pages.cast<Paged<Friend>>()),
    );
  }

  /// One heading per non-empty bucket, then its rows. A single-bucket tab
  /// carries no heading: a label over the only list on screen names nothing.
  Widget _list(BuildContext context, List<Paged<Friend>> pages) {
    final rows = <Widget>[];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].isEmpty) continue;
      if (pages.length > 1) {
        rows.add(SectionHeader(label: _headingFor(_buckets[i])));
      }
      rows.addAll([for (final friend in pages[i].items) _row(context, friend)]);
    }
    if (pages.any((page) => page.hasMore)) rows.add(_footer());

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  String _headingFor(FriendBucket bucket) => switch (bucket) {
    FriendBucket.incoming => 'Wants to be friends',
    FriendBucket.outgoing => 'Waiting for them',
    FriendBucket.friends => 'Friends',
    FriendBucket.blocked => 'Blocked',
  };

  /// The spinner at the end of a page, which is also what says the list has
  /// not simply stopped.
  Widget _footer() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

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
