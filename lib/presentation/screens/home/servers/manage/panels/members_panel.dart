import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/loading_block.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../invites/show_invite_modal.dart';
import '../../../members/widgets/members_list.dart';
import '../../../members/widgets/members_search_field.dart';
import '../widgets/manage_panel.dart';

/// The members page of the manage-server dialog — everyone on [server] with
/// their roles and moderation state. Server admins manage roles here
/// (Discord-style: invites grant nothing, promotion happens after joining);
/// admins and channel managers get mute/deafen controls.
///
/// **Drawn from [ServerMembersCubit]**, the same roster the sidebar reads —
/// the dialog's own for [server] when it is not the one on screen. It used to
/// page the roster itself, keep its own chips, and patch a row after a mute
/// or ban, so a change made anywhere else while it was open never reached it.
/// Now a mute, a role, a rename or a ban lands here the way it lands in the
/// sidebar: the server's doorbell, then the roster's re-read.
///
/// The roster is paged and searching is the database's job (`member_counts`,
/// `search_members`). Banned members are included on purpose, here and
/// nowhere else: lifting a ban means finding the person it is on. They and
/// the bots are short, whole lists and come first; the paged people come
/// last, because the end of the list is what asks for the next page.
class MembersPanel extends StatefulWidget {
  final Server server;

  const MembersPanel({super.key, required this.server});

  @override
  State<MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends State<MembersPanel> {
  /// Held for [dispose], where the tree can no longer be asked for it.
  late final ServerMembersCubit _members;

  /// Whether a search is waiting on the database. The answer itself is the
  /// roster's ([ServerMembersState.search]).
  bool _searching = false;
  String _query = '';

  String? _error;
  String? _expandedId;

  /// Member id with an in-flight moderation call.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _members = context.read<ServerMembersCubit>();
    unawaited(_members.showBanned());
  }

  @override
  void dispose() {
    _members.stopShowingBanned();
    // The search is this page's question; the next visit starts without it.
    unawaited(_members.search(''));
    super.dispose();
  }

  Future<void> _search(String query) async {
    _query = query;
    setState(() => _searching = query.trim().isNotEmpty);
    await _members.search(query);
    if (!mounted || query != _query) return;
    setState(() => _searching = false);
  }

  Future<void> _moderate(
    ServerMember member, {
    bool? muted,
    bool? deafened,
    bool? banned,
    bool kick = false,
  }) async {
    setState(() {
      _busyId = member.id;
      _error = null;
    });
    final cubit = context.read<ServerCubit>();
    final response = kick
        ? await cubit.kickMember(userId: member.id, serverId: widget.server.id)
        : await cubit.moderateUser(
            userId: member.id,
            isMuted: muted,
            isDeafened: deafened,
            isBanned: banned,
            serverId: widget.server.id,
          );
    // Shown once the roster has re-read it: the doorbell would bring the same
    // answer a moment later, and a button that has said yes should not wait
    // for it.
    if (response.success) await _members.refresh();
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (!response.success) _error = response.error;
    });
  }

  /// What the list shows: the search's answer while there is one, otherwise
  /// the banned, the bots and the people loaded so far.
  List<ServerMember> _rows(ServerMembersState roster) {
    final search = roster.search;
    if (search != null) return search.matches;
    return [
      ...?roster.banned,
      for (final bot in roster.bots)
        if (!bot.isBanned) bot,
      // A ban lands on a paged row before the pages are read again; the
      // banned list above is where that person is now.
      for (final person in roster.people.members)
        if (!person.isBanned) person,
    ];
  }

  @override
  Widget build(BuildContext context) {
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

    return BlocBuilder<ServerMembersCubit, ServerMembersState>(
      builder: (context, roster) => ManagePanel(
        title: 'Members',
        subtitle: roster.loaded
            ? [
                roster.peopleCount == 1
                    ? '1 member'
                    : '${roster.peopleCount} members',
                if (roster.bots.length == 1)
                  '1 bot'
                else if (roster.bots.length > 1)
                  '${roster.bots.length} bots',
              ].join(' · ')
            : widget.server.name,
        footer: [
          if (viewerPerms?.canCreateTokens ?? false)
            AppButton(
              label: 'Invite people',
              icon: const Icon(Icons.person_add_outlined, size: K.iconRow),
              onPressed: () => showInviteModal(context, server: widget.server),
            ),
        ],
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
                roster,
                themeState,
                viewer?.id,
                viewerIsAdmin,
                viewerIsModerator,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    child: MessageBanner(message: _error!, kind: MessageBannerKind.error),
  );

  Widget _buildBody(
    ServerMembersState roster,
    ThemeState themeState,
    String? viewerId,
    bool viewerIsAdmin,
    bool viewerIsModerator,
  ) {
    final isSearching = roster.search != null;
    if (_searching || (!roster.loaded && !isSearching)) {
      return const LoadingBlock(padding: EdgeInsets.all(32));
    }

    final rows = _rows(roster);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          isSearching ? 'Nobody matches that name.' : 'Nobody here yet.',
          textAlign: TextAlign.center,
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
      );
    }

    return MembersList(
      members: rows,
      // A search is one ranked answer, not the first of many: `search_members`
      // caps it and there is no coherent cursor into a ranked order.
      hasMore: !isSearching && roster.hasMorePeople,
      onLoadMore: () => unawaited(_members.loadMorePeople()),
      memberRoles: roster.memberRoles,
      serverId: widget.server.id,
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
