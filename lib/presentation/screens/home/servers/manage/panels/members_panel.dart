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
import '../../../../../theme/app_text.dart';
import '../../../../../common/loading_dots.dart';
import '../../../../../common/message_banner.dart';
import '../../../members/widgets/members_list.dart';
import '../../../members/widgets/members_search_field.dart';
import '../widgets/manage_panel.dart';

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
/// **The roster is paged, and searching is the database's job** (migration
/// 039). This page used to read every member in one call, which PostgREST cut
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

  /// How many members there are, from the database rather than from the length
  /// of what has been loaded.
  int? _total;

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
    setState(() => _total = counts.people + counts.bots);
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
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
          subtitle: switch (_total) {
            null => widget.server.name,
            1 => '1 member',
            final n => '$n members',
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
      },
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
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: LoadingDots(color: themeState.accentBright, dotSize: 6),
        ),
      );
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
