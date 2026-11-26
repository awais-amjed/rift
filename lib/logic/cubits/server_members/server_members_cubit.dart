import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/apis/members_api.dart';
import '../../../data/apis/roles_api.dart';
import '../../../data/classes/member_page.dart';
import '../../../data/classes/role.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_member.dart';
import '../../../data/repositories/session_repository.dart';
import '../../services/member_roster_pager.dart';
import '../../services/server_topic_watcher.dart';
import '../../services/server_topics.dart';

part 'server_members_page.dart';
part 'server_members_refresh.dart';
part 'server_members_roles.dart';
part 'server_members_state.dart';

/// One server's members, kept live and kept bounded. Each server's context
/// holds one (`ServerContext`), so a call's roster stays the call's server's
/// whichever server is being read.
///
/// Presence (who is *online*) has always been realtime; membership (who is
/// *here at all*) was fetched once per server and cached until you switched
/// away, so somebody who joined while you were looking never appeared. The
/// database says `members` on the server's topic whenever a `users` row moves,
///and [ServerTopicWatcher] turns that into a refresh — which
/// covers renames, new avatars, permission changes and bans as well as joins.
///
/// **What changed with the member directory.** That refresh used to be three
/// full-table reads: every member, every role, every role assignment, on every
/// `users` row event. Somebody else changing their nickname cost the whole
/// roster, and the roster was silently cut at 1000 rows anyway. Now:
///
///  * bots are fetched whole, because there are a handful of them;
///  * people are paged alphabetically, as far as the sidebar is scrolled;
///  * anybody we hold an *id* for — presence, a call, a message author — is
///    resolved by id, which is bounded by who is actually about;
///  * a `members` event re-resolves only what is on screen, rather than
///    re-reading the server.
class ServerMembersCubit extends Cubit<ServerMembersState>
    with _MembersRolesMixin, _MembersPageMixin, _MembersRefreshMixin {
  final SessionRepository _session;
  @override
  late final ServerTopicWatcher _watcher;

  @override
  MembersApi _membersOn(String serverId) => MembersApi(_session.on(serverId));
  @override
  RolesApi _rolesOn(String serverId) => RolesApi(_session.on(serverId));
  @override
  late final MemberRosterPager _people = MemberRosterPager(
    fetchPage: _fetchPeoplePage,
  );

  /// Guards against a slow fetch landing after a newer one, or after a switch.
  @override
  int _loadId = 0;

  final List<StreamSubscription<void>> _idSubs = [];

  /// Keep the online members nameable, whoever they are.
  ///
  /// Presence reports *ids*, and with the roster paged an id is routinely
  /// somebody no page has reached — the sidebar's Online group would be a list
  /// of the people who happen to sort early in the alphabet. So every presence
  /// tick resolves what it names; ids already held cost nothing.
  ///
  /// Wired from the outside rather than injected because the presence cubit
  /// is built beside this one, not before it. Called once per source: the
  /// server's presence, and the call's participants while the call is here.
  void watchPresence(Stream<Set<String>> onlineIds) {
    _idSubs.add(onlineIds.listen((ids) => unawaited(resolve(ids))));
  }

  ServerMembersCubit({
    required SessionRepository session,
    required String serverId,
  }) : _session = session,
       super(ServerMembersState()) {
    _watcher = ServerTopicWatcher(
      session: session,
      watchedServerId: serverId,
      topicOf: (server) => ServerTopics.server(server.id),
      event: ServerEvent.members,
      onNamed: (ids) => unawaited(refresh(named: ids)),
      // About a millisecond for each person here, up to two seconds: nothing
      // on a small server, and on one of thousands the answers to one ring
      // arrive over two seconds rather than in the same quarter second.
      spreadUpTo: () =>
          Duration(milliseconds: state.peopleCount.clamp(0, 2000)),
      onServerChanged: _onServerChanged,
    );
  }

  /// This server answered that it has no `member_sidebar`, so the wasted round
  /// trip is not made again on this server until the app next starts.
  bool _noSidebarCall = false;

  void _onServerChanged(Server? server) {
    if (isClosed) return;
    _loadId++;
    _noSidebarCall = false;
    _noRefreshCall = false;
    _people.reset();
    if (server == null) {
      emit(ServerMembersState());
      return;
    }
    emit(ServerMembersState(serverId: server.id, loading: true));
    unawaited(_loadFirst());
  }

  // ── Loading ─────────────────────────────────────────────────

  Future<MemberPage?> _fetchPeoplePage(
    ({String name, String id})? after,
  ) async {
    final serverId = _watcher.serverId;
    if (serverId == null) return null;
    final result = await _membersOn(
      serverId,
    ).listMembers(bots: false, after: after);
    return result.page;
  }

  /// Everything the sidebar needs to draw its first frame: the bots, the first
  /// page of people, how many there are, and the roles behind the chips.
  @override
  Future<void> _loadFirst() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final loadId = ++_loadId;

    final read = _noSidebarCall ? null : await _membersOn(serverId).sidebar();
    if (_stale(loadId, serverId)) return;
    if (read?.unsupported ?? false) _noSidebarCall = true;

    final sidebar = read?.sidebar;
    if (sidebar == null) {
      await _loadFirstOneByOne(serverId, loadId);
    } else {
      // A bot is somebody's program, so a page of them is already past any
      // real server, but the list is meant to be whole.
      final bots = sidebar.bots.hasMore
          ? await _membersOn(serverId).listBots()
          : sidebar.bots.members;
      if (_stale(loadId, serverId)) return;
      _people.seed(sidebar.people);
      _emitLoaded(
        state.copyWith(
          bots: bots,
          people: _people.loaded,
          peopleCount: sidebar.peopleCount,
          roles: sidebar.roles,
          memberRoles: {
            ...state.memberRoles,
            // Holders and non-holders alike, as `_loadRoles` records them.
            for (final member in [
              ...sidebar.bots.members,
              ...sidebar.people.members,
            ])
              member.id: sidebar.memberRoles[member.id] ?? const [],
          },
          loaded: true,
          loading: false,
        ),
      );
    }
    if (_stale(loadId, serverId)) return;
    await _loadRoles([
      for (final member in [...state.bots, ..._people.loaded.members])
        member.id,
    ]);
    if (_countingRoles) await _countRoles();
    await _refreshExtras();
  }

  /// The same for a server not updated to answer `member_sidebar` yet: its
  /// requests all at once, since none needs another, and the role chips after.
  Future<void> _loadFirstOneByOne(String serverId, int loadId) async {
    final (bots, counts, roles, _) = await (
      _membersOn(serverId).listBots(),
      _membersOn(serverId).memberCounts(),
      _rolesOn(serverId).listRoles(),
      _people.next(),
    ).wait;
    if (_stale(loadId, serverId)) return;

    _emitLoaded(
      state.copyWith(
        bots: bots,
        people: _people.loaded,
        peopleCount: counts.people,
        roles: roles,
        loaded: true,
        loading: false,
      ),
    );
  }

  /// Page in more people — what the sidebar asks for as it is scrolled.
  Future<void> loadMorePeople() async {
    final serverId = _watcher.serverId;
    if (serverId == null || !await _people.next()) return;
    if (isClosed || serverId != _watcher.serverId) return;

    emit(state.copyWith(people: _people.loaded));
    await _loadRoles([for (final member in _people.loaded.members) member.id]);
  }

  /// Fetch the members behind [userIds] that we cannot already name.
  ///
  /// This is what keeps a name on screen for somebody the pages have not
  /// reached — a participant in a call, an author in the scrollback, anybody
  /// Realtime presence says is online. Ids we already hold cost nothing, so a
  /// caller may hand over the same set on every presence tick.
  Future<void> resolve(Iterable<String> userIds) async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final wanted = [
      for (final id in userIds)
        if (!state.byId.containsKey(id)) id,
    ];
    if (wanted.isEmpty) return;

    final found = await _membersOn(serverId).membersByIds(wanted);
    if (isClosed || serverId != _watcher.serverId || found.isEmpty) return;

    _emitLoaded(
      state.copyWith(
        known: {...state.known, for (final member in found) member.id: member},
      ),
    );
    await _loadRoles([for (final member in found) member.id]);
  }

  /// Whether a load that started as [loadId] is still the one we want.
  @override
  bool _stale(int loadId, String serverId) =>
      isClosed || loadId != _loadId || serverId != _watcher.serverId;

  @override
  void _emitLoaded(ServerMembersState next) => emit(next);

  @override
  Future<void> close() async {
    for (final sub in _idSubs) {
      await sub.cancel();
    }
    await _watcher.dispose();
    return super.close();
  }
}
