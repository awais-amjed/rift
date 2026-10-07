import 'package:flutter/material.dart';

import '../../../../../data/classes/participant_setting.dart';
import '../../../../../data/classes/role.dart';
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
///
/// A row is handed back unchanged while what it shows is (`_rows`), and each
/// row tells the list where it went when somebody above it comes online, so a
/// presence change rebuilds the rows that changed rather than the screenful.
class MembersSidebarList extends StatefulWidget {
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
  State<MembersSidebarList> createState() => _MembersSidebarListState();
}

/// What a [MemberRow] is built from. Members, settings and roles are compared
/// by identity, which the cubits keep for anything that did not change.
typedef _RowInputs = ({
  ServerMember member,
  bool isOnline,
  bool isMe,
  ParticipantSetting? setting,
  Role? role,
  Role? colourRole,
});

class _MembersSidebarListState extends State<MembersSidebarList> {
  /// Each member's row as last built, and what it was built from.
  final _rows = <String, ({_RowInputs inputs, Widget row})>{};

  @override
  void reassemble() {
    super.reassemble();
    // A hot reload changes how rows are built, not what they are built from.
    _rows.clear();
  }

  @override
  Widget build(BuildContext context) {
    final roster = widget.roster;
    final onlineIds = widget.onlineIds;
    final split = MemberRoster.split(
      bots: roster.bots,
      known: roster.known.values,
      people: roster.people.members,
      onlineIds: onlineIds,
    );

    // A row is found again by its member's key, and two rows may not share
    // one: a page that overlaps the last would otherwise draw somebody twice.
    final drawn = <String>{};
    final entries = <_Entry>[
      // Above the people, and in a section of their own: a bot is not a quiet
      // member, it is a program that hears only what it is told (BOTS.md §9).
      // Each row still shows whether it is connected — for a bot that is "is
      // it running", which is worth seeing.
      ..._group(label: 'Bots', members: split.bots, drawn: drawn),
      ..._group(label: 'Online', members: split.online, drawn: drawn),
      ..._group(
        label: 'Offline',
        members: split.offline,
        drawn: drawn,
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
    final placeOf = <Key, int>{
      for (var i = 0; i < entries.length; i++) entries[i].key: i,
    };
    _rows.removeWhere((id, _) => !placeOf.containsKey(_Entry.memberKey(id)));

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (roster.hasMorePeople &&
            notification.metrics.extentAfter <
                MembersSidebarList._loadMoreSlack) {
          widget.onLoadMore();
        }
        // Never swallowed — the scrollbar and any parent are still listening.
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
        itemCount: entries.length,
        findChildIndexCallback: (key) => placeOf[key],
        itemBuilder: (context, index) => _row(entries[index]),
      ),
    );
  }

  /// One entry, built only once it is close enough to the viewport to matter.
  Widget _row(_Entry entry) {
    final member = entry.member;
    if (member == null) {
      return entry.label == null
          ? ListLoadingFooter(key: entry.key)
          : SectionHeader(key: entry.key, label: entry.label!);
    }
    final _RowInputs inputs = (
      member: member,
      // Takes the online set rather than a flag, because the Bots group holds
      // both — its rows are grouped by *being a bot* and lit by whether that
      // bot is currently connected.
      isOnline: widget.onlineIds.contains(member.id),
      isMe: member.id == widget.myId,
      setting: widget.appState.participantSettings[member.id],
      role: widget.roster.topRoleFor(member.id),
      colourRole: widget.roster.colourRoleFor(member.id),
    );
    final kept = _rows[member.id];
    if (kept != null && kept.inputs == inputs) return kept.row;
    final row = MemberRow(
      key: entry.key,
      member: inputs.member,
      isOnline: inputs.isOnline,
      isMe: inputs.isMe,
      setting: inputs.setting,
      role: inputs.role,
      colourRole: inputs.colourRole,
    );
    _rows[member.id] = (inputs: inputs, row: row);
    return row;
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
    required Set<String> drawn,
    int? total,
  }) {
    if (members.isEmpty) return const [];
    return [
      _Entry.header('$label — ${total ?? members.length}', label),
      for (final member in members)
        if (drawn.add(member.id)) _Entry.member(member),
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

  /// Which group a header heads. Its label carries a count, which changes.
  final String? group;

  const _Entry.header(this.label, this.group) : member = null;
  const _Entry.member(this.member) : label = null, group = null;
  const _Entry.footer() : label = null, member = null, group = null;

  static Key memberKey(String id) => ValueKey('member:$id');

  /// Where the list finds this entry's row again after the entries above it
  /// change.
  Key get key => switch ((member, group)) {
    (final ServerMember member, _) => memberKey(member.id),
    (_, final String group) => ValueKey('group:$group'),
    _ => const ValueKey('footer'),
  };
}
