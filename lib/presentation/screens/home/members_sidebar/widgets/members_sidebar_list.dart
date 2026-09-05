import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/services/member_roster.dart';
import '../../channels/channel_list/widgets/section_header.dart';
import 'member_row.dart';

/// The three groups inside the member sidebar: bots, online, offline.
///
/// Its own widget because the offline group **pages** (migration 039). The
/// sidebar used to be handed the whole roster and draw it, which was fine at
/// fifty members and quietly wrong past a thousand — PostgREST cut the fetch
/// there and the sidebar reported the truncation as the membership. Now
/// Offline is a window onto an alphabetical list, its header counts what the
/// database says rather than what has been loaded, and scrolling near the
/// bottom asks for more.
///
/// Bots and Online do not page, and it is worth saying why they need not: a
/// bot is a program somebody runs, so there are a handful; and Online is
/// bounded by who is actually connected, not by who has ever joined.
class MembersSidebarList extends StatelessWidget {
  final AppState appState;
  final ServerMembersState roster;
  final Set<String> onlineIds;
  final String? myId;

  /// Asked for when the list is scrolled near its end. Safe to fire often —
  /// `MemberRosterPager` drops a call made while one is already in flight.
  final VoidCallback onLoadMore;

  const MembersSidebarList({
    super.key,
    required this.appState,
    required this.roster,
    required this.onlineIds,
    required this.myId,
    required this.onLoadMore,
  });

  /// How close to the bottom counts as "nearly there" — roughly three rows, so
  /// the next page is asked for while there is still something to read.
  static const double _loadMoreSlack = 150;

  @override
  Widget build(BuildContext context) {
    final split = MemberRoster.split(
      bots: roster.bots,
      known: roster.known.values,
      people: roster.people.members,
      onlineIds: onlineIds,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (roster.hasMorePeople &&
            notification.metrics.extentAfter < _loadMoreSlack) {
          onLoadMore();
        }
        // Never swallowed — the scrollbar and any parent are still listening.
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          // Above the people, and in a section of their own: a bot is not a
          // quiet member, it is a program that hears only what it is told
          // (BOTS.md §9). Each row still shows whether it is connected — for a
          // bot that is "is it running", which is worth seeing.
          ..._group(label: 'Bots', members: split.bots),
          ..._group(label: 'Online', members: split.online),
          ..._group(
            label: 'Offline',
            members: split.offline,
            // What the server says, not what has been scrolled to. The people
            // count excludes bots and banned members, and everybody not in the
            // online set is offline whether or not their page has arrived.
            total: (roster.peopleCount - split.online.length).clamp(
              split.offline.length,
              // A count that has not loaded yet must never read as *fewer*
              // than the rows already on screen.
              1 << 30,
            ),
          ),
          if (roster.hasMorePeople) _buildFooter(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// One group: the shared [SectionHeader] plus its rows. Empty groups render
  /// nothing rather than a lone "Offline — 0".
  ///
  /// [total] is what the header counts when the group is a window onto a longer
  /// list; without it the header counts the rows, which is the right answer for
  /// a group that is all there.
  List<Widget> _group({
    required String label,
    required List<ServerMember> members,
    int? total,
  }) {
    if (members.isEmpty) return const [];
    return [
      SectionHeader(label: '$label — ${total ?? members.length}'),
      for (final member in members)
        MemberRow(
          member: member,

          // Takes the online set rather than a flag, because the Bots group
          // holds both — its rows are grouped by *being a bot* and lit by
          // whether that bot is currently connected.
          isOnline: onlineIds.contains(member.id),
          isMe: member.id == myId,
          setting: appState.participantSettings[member.id],
          role: roster.topRoleFor(member.id),
          colourRole: roster.colourRoleFor(member.id),
        ),
    ];
  }

  Widget _buildFooter() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
