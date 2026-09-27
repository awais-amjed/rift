import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/services/member_roster.dart';
import '../../../../common/list_loading_footer.dart';
import '../../channels/channel_list/widgets/section_header.dart';
import 'member_row.dart';

/// The three groups inside the member sidebar: bots, online, offline.
///
/// Its own widget because the offline group **pages** (`member_directory`). The
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
///
/// Built lazily, which matters for the same reason the paging does. The rows
/// were `ListView(children: […])`, so every offline member that had ever been
/// paged in was built and kept alive on every rebuild — the list pages
/// precisely because that set is unbounded, and building all of it gives back
/// what the paging was for. Flattening the three groups into one index space
/// is what lets `ListView.builder` do it.
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

    final entries = <_Entry>[
      // Above the people, and in a section of their own: a bot is not a quiet
      // member, it is a program that hears only what it is told (BOTS.md §9).
      // Each row still shows whether it is connected — for a bot that is "is
      // it running", which is worth seeing.
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
          // A count that has not loaded yet must never read as *fewer* than
          // the rows already on screen.
          1 << 30,
        ),
      ),
      if (roster.hasMorePeople) const _Entry.footer(),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (roster.hasMorePeople &&
            notification.metrics.extentAfter < _loadMoreSlack) {
          onLoadMore();
        }
        // Never swallowed — the scrollbar and any parent are still listening.
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
        itemCount: entries.length,
        itemBuilder: (context, index) => _row(entries[index]),
      ),
    );
  }

  /// One entry, built only once it is close enough to the viewport to matter.
  Widget _row(_Entry entry) {
    final member = entry.member;
    if (member == null) {
      return entry.label == null
          ? const ListLoadingFooter()
          : SectionHeader(label: entry.label!);
    }
    return MemberRow(
      member: member,

      // Takes the online set rather than a flag, because the Bots group holds
      // both — its rows are grouped by *being a bot* and lit by whether that
      // bot is currently connected.
      isOnline: onlineIds.contains(member.id),
      isMe: member.id == myId,
      setting: appState.participantSettings[member.id],
      role: roster.topRoleFor(member.id),
      colourRole: roster.colourRoleFor(member.id),
    );
  }

  /// One group: the shared [SectionHeader] plus its rows. Empty groups render
  /// nothing rather than a lone "Offline — 0".
  ///
  /// [total] is what the header counts when the group is a window onto a longer
  /// list; without it the header counts the rows, which is the right answer for
  /// a group that is all there.
  List<_Entry> _group({
    required String label,
    required List<ServerMember> members,
    int? total,
  }) {
    if (members.isEmpty) return const [];
    return [
      _Entry.header('$label — ${total ?? members.length}'),
      for (final member in members) _Entry.member(member),
    ];
  }
}

/// One line of the flattened list: a group header, a member, or the footer.
///
/// A plain value rather than a widget, which is the point — the list holds one
/// of these per member and builds a widget only for the handful on screen.
class _Entry {
  final String? label;
  final ServerMember? member;

  const _Entry.header(this.label) : member = null;
  const _Entry.member(this.member) : label = null;
  const _Entry.footer() : label = null, member = null;
}
