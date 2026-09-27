import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/member_page.dart';
import '../../../../../../data/classes/role.dart';
import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/services/member_roster_pager.dart';
import '../../../../../common/loading_block.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../members/widgets/members_list.dart';
import '../../../members/widgets/members_search_field.dart';
import '../widgets/manage_panel.dart';

/// Over the widget budget and one job: the members page — the list, and the
/// role and moderation actions on each row.
///
/// The members page of the manage-server dialog — everyone on [server] with
/// their roles and moderation state. Server admins manage permissions here (Discord-style:
/// invites grant nothing, promotion happens after joining); admins and
/// channel managers get mute/deafen controls.
///
/// Takes the server rather than reading the selection: the dialog opens from
/// the rail's menu, which can be a server you are not currently looking at. Every call it
/// makes names that server, so the roster and the permission writes cannot drift
/// onto a different one.
///
/// **The roster is paged, and searching is the database's job**.
/// This page used to read every member in one call, which PostgREST cut
/// at 1000 rows — so on a large server the last members alphabetically could
/// not be moderated at all, and the header confidently reported a membership of
/// exactly a thousand. Now it walks pages as you scroll, counts with
/// `member_counts`, and answers a typed name with `search_members`.
///
/// Banned members are included on purpose, here and nowhere else: lifting a ban
/// means finding the person it is on.
class MembersPanel extends StatefulWidget {
  final Server server;

  const MembersPanel({super.key, required this.server});

  @override
  State<MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends State<MembersPanel> {
  late final MemberRosterPager _pager = MemberRosterPager(
    fetchPage: _fetchPage,
  );

  /// Matches from the search field, or null when the field is empty and the
  /// paged list is what is on screen.
  ///
  /// A separate list rather than a filter over the pager's, because a search is
  /// answered by the database over the whole roster — including people no page
  /// has reached yet, which is the entire point of it.
  List<ServerMember>? _matches;
  bool _searching = false;

  /// Guards a slow search landing after a newer one, or after the field was
  /// cleared.
  int _searchId = 0;

  /// What the field last asked, so a reload can ask it again. A search is
  /// answered over the whole roster, so re-running it is the only way to
  /// refresh a matched row — resetting the pager refreshes the list the
  /// matches are standing in front of.
  String _query = '';

  /// Moderation applied since the page a member arrived on.
  ///
  /// Held apart rather than written into the pager's list: the pager owns what
  /// the server said, and a mute is something this dialog did afterwards. It
  /// also survives a search, so muting somebody and then searching for them
  /// does not show them unmuted again.
  final Map<String, ServerMember> _moderated = {};

  /// Which roles each visible member holds. Filled per page rather than for the
  /// whole server — `member_role_list` is one row per (member, role), so it hit
  /// the response ceiling sooner than the roster itself did.
  Map<String, List<Role>> _memberRoles = const {};

  /// How many people and how many bots there are, from the database rather
  /// than from the length of what has been loaded.
  ///
  /// Counted apart, and said apart, because "members" has to mean the same
  /// thing everywhere it is written. The roster and the phone's channel
  /// header both mean people by it, so a total that folded the bots in made
  /// this page disagree with both of them about the same server.
  ({int people, int bots})? _counts;

  String? _error;
  String? _expandedId;

  /// Member id with an in-flight permission/moderation call.
  String? _busyId;

  /// What the list is showing: matches while searching, otherwise the pages
  /// loaded so far — each row with any moderation applied since it arrived.
  List<ServerMember> get _rows => [
    for (final member in _matches ?? _pager.loaded.members)
      _moderated[member.id] ?? member,
  ];

  bool get _isSearching => _matches != null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
    unawaited(_loadTotal());
  }

  Future<MemberPage?> _fetchPage(({String name, String id})? after) async {
    final result = await context.read<ServerCubit>().listMembers(
      serverId: widget.server.id,
      after: after,
      // Null, not false: this is the one screen that has to reach a banned
      // member, because lifting a ban means finding the person it is on.
      banned: null,
    );
    if (!result.success && mounted) setState(() => _error = result.error);
    return result.page;
  }

  Future<void> _loadMore() async {
    if (!await _pager.next() || !mounted) return;
    setState(() {});
    await _loadRoles(_pager.loaded.members);
  }

  Future<void> _loadTotal() async {
    final counts = await context.read<ServerCubit>().memberCounts(
      serverId: widget.server.id,
    );
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  /// Role chips for [members], merged into what is already known.
  ///
  /// Asked for the rows on screen rather than the whole server, and merged
  /// rather than replaced so a page does not blank the chips on the pages above
  /// it.
  Future<void> _loadRoles(List<ServerMember> members) async {
    final wanted = [
      for (final member in members)
        if (!_memberRoles.containsKey(member.id)) member.id,
    ];
    if (wanted.isEmpty) return;

    final roles = await context.read<ServerCubit>().memberRolesFor(wanted);
    if (!mounted) return;
    setState(() {
      _memberRoles = {
        ..._memberRoles,
        // Everybody asked about is recorded, holders and non-holders alike, or
        // the next page would ask about them all over again.
        for (final id in wanted) id: roles[id] ?? const [],
      };
    });
  }

  Future<void> _search(String query) async {
    final id = ++_searchId;
    _query = query;
    if (query.trim().isEmpty) {
      setState(() {
        _matches = null;
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    final results = await context.read<ServerCubit>().searchMembers(
      query: query,
      serverId: widget.server.id,
      banned: null,
    );
    if (!mounted || id != _searchId) return;
    setState(() {
      _matches = results;
      _searching = false;
    });
    await _loadRoles(results);
  }

  Future<void> _moderate(
    ServerMember member, {
    bool? muted,
    bool? deafened,
    bool? banned,
  }) async {
    setState(() => _busyId = member.id);
    final response = await context.read<ServerCubit>().moderateUser(
      userId: member.id,
      isMuted: muted,
      isDeafened: deafened,
      isBanned: banned,
      serverId: widget.server.id,
    );
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (response.success) {
        _moderated[member.id] = member.copyWith(
          isMuted: muted,
          isDeafened: deafened,
          isBanned: banned,
        );
      } else {
        _error = response.error;
      }
    });
  }

  /// Forget what the page holds about people and ask again.
  ///
  /// After a transfer, two rows changed at once — ours and the new owner's —
  /// and after the roles dialog, one did. Both change the same two things:
  /// the chips, and the **row**, because `ADMINISTRATOR` is folded into
  /// `users.is_server_admin` by a trigger.
  ///
  /// The row is why this resets the pager rather than only the chips. An admin
  /// is never a moderation target, so the panel hides Ban for one — off the
  /// row it was handed. Reloading the chips alone left that row saying
  /// "ordinary member", and the page went on offering a ban that comes back
  /// *Admins cannot be moderated* after a confirm dialog. Losing the scroll
  /// position is the right price: both callers are a deliberate act on one
  /// person, not something that happens while reading.
  Future<void> _reloadPeople() async {
    _pager.reset();
    setState(() {
      _memberRoles = const {};
      _moderated.clear();
    });
    await _loadMore();
    if (!mounted) return;
    if (_query.trim().isNotEmpty) await _search(_query);
  }

  bool _ownsIt(ServerState state) =>
      state.serverById(widget.server.id)?.user?.permissions.isOwner ?? false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<ServerCubit, ServerState>(
      listenWhen: (previous, next) => _ownsIt(previous) != _ownsIt(next),
      listener: (_, _) => unawaited(_reloadPeople()),
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final themeState = context.theme;
    // Live rather than read off the passed-in snapshot, so being demoted
    // while the dialog is open takes the controls away.
    final viewer = context
        .watch<ServerCubit>()
        .state
        .serverById(widget.server.id)
        ?.user;
    final viewerPerms = viewer?.permissions;
    final viewerIsAdmin = viewerPerms?.isServerAdmin ?? false;
    final viewerIsModerator =
        viewerIsAdmin || (viewerPerms?.isChannelManager ?? false);

    return ManagePanel(
      title: 'Members',
      subtitle: switch (_counts) {
        null => widget.server.name,
        final c => [
          c.people == 1 ? '1 member' : '${c.people} members',
          if (c.bots == 1) '1 bot' else if (c.bots > 1) '${c.bots} bots',
        ].join(' · '),
      },
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: MembersSearchField(
              onChanged: (query) => unawaited(_search(query)),
            ),
          ),
          if (_error != null) _buildError(),
          Expanded(
            child: _buildBody(
              themeState,
              viewer?.id,
              viewerIsAdmin,
              viewerIsModerator,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    child: MessageBanner(message: _error!, kind: MessageBannerKind.error),
  );

  Widget _buildBody(
    ThemeState themeState,
    String? viewerId,
    bool viewerIsAdmin,
    bool viewerIsModerator,
  ) {
    if (_searching || (!_pager.isLoaded && !_isSearching)) {
      return const LoadingBlock(padding: EdgeInsets.all(32));
    }

    final rows = _rows;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _isSearching ? 'Nobody matches that name.' : 'Nobody here yet.',
          textAlign: TextAlign.center,
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
      );
    }

    return MembersList(
      members: rows,

      // A search is one ranked answer, not the first of many: `search_members`
      // caps it and there is no coherent cursor into a ranked order.
      hasMore: !_isSearching && _pager.hasMore,
      onLoadMore: () => unawaited(_loadMore()),
      memberRoles: _memberRoles,
      onRolesChanged: () => unawaited(_reloadPeople()),
      viewerId: viewerId,
      viewerIsAdmin: viewerIsAdmin,
      viewerIsModerator: viewerIsModerator,
      expandedId: _expandedId,
      busyId: _busyId,
      onTap: (member) => setState(() {
        _expandedId = _expandedId == member.id ? null : member.id;
      }),
      onModerate: _moderate,
    );
  }
}
