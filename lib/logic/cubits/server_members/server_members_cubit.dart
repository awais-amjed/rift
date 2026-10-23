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
    with _MembersRolesMixin, _MembersPageMixin {
  final SessionRepository _session;
  @override
  late final ServerTopicWatcher _watcher;

  @override
  MembersApi _membersOn(String serverId) => MembersApi(_session.on(serverId));
  @override
  RolesApi _rolesOn(String serverId) => RolesApi(_session.on(serverId));
  late final MemberRosterPager _people = MemberRosterPager(
    fetchPage: _fetchPeoplePage,
  );

  /// Guards against a slow fetch landing after a newer one, or after a switch.
  int _loadId = 0;

  final List<StreamSubscription<void>> _idSubs = [];

  void Function()? _onSelfModerationChanged;

  /// Called when the local user's own mute/deafen state changes — see
  /// [_notifySelfModeration].
  void setOnSelfModerationChanged(void Function() callback) =>
      _onSelfModerationChanged = callback;

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
      onChanged: () => unawaited(refresh()),
      onServerChanged: _onServerChanged,
    );
  }

  void _onServerChanged(Server? server) {
    if (isClosed) return;
    _loadId++;
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
  Future<void> _loadFirst() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final loadId = ++_loadId;

    final bots = await _membersOn(serverId).listBots();
    final counts = await _membersOn(serverId).memberCounts();
    final roles = await _rolesOn(serverId).listRoles();
    await _people.next();
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
    await _loadRoles([
      for (final member in [...bots, ..._people.loaded.members]) member.id,
    ]);
    if (_countingRoles) await _countRoles();
    await _refreshExtras();
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

  /// A `users` row changed. Re-read what is on screen, and nothing else.
  ///
  /// A rename, an avatar, a mute, a ban or a join all arrive here. The old
  /// answer was to refetch the server; the new one is to refetch the members
  /// this client is currently able to name, which is bounded by the sidebar and
  /// the call rather than by how many people have ever joined. A join shows up
  /// through [peopleCount] and, once somebody scrolls to them, through the
  /// pages — except when every page is already loaded, where there is nothing
  /// left to scroll to, so the roster is read again from the top.
  Future<void> refresh() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    if (!state.loaded) return _loadFirst();
    final loadId = ++_loadId;

    final bots = await _membersOn(serverId).listBots();
    final counts = await _membersOn(serverId).memberCounts();
    final roles = await _rolesOn(serverId).listRoles();

    // The pages reach a joiner only when somebody scrolls to them, which is
    // never when every page is already loaded: the count went up and the row
    // did not appear. With the whole roster in hand and the count moved, read
    // it again from the top — as far as it was — so a join, or a ban, lands.
    var repaged = false;
    if (!state.people.hasMore && counts.people != state.people.members.length) {
      final reach = state.people.members.length;
      _people.reset();
      while (await _people.next() &&
          _people.loaded.members.length < reach &&
          _people.hasMore) {}
      if (_stale(loadId, serverId)) return;
      // A read that failed part way leaves what was on screen, not nothing.
      repaged = _people.loaded.members.isNotEmpty || counts.people == 0;
    }

    // Everybody we hold, paged or resolved by id: somebody known only from a
    // call or a message kept their old name and picture until they left.
    final refreshed = await _membersOn(serverId).membersByIds(
      {
        ...(repaged ? _people.loaded : state.people).members.map((m) => m.id),
        ...state.known.keys,
      }.toList(),
    );
    if (_stale(loadId, serverId)) return;

    final byId = {for (final member in refreshed) member.id: member};
    _emitLoaded(
      state.copyWith(
        bots: bots,
        peopleCount: counts.people,
        // Every server has its baseline role, so none back means the read
        // failed — keep the ladder on screen rather than blanking it.
        roles: roles.isEmpty ? null : roles,
        // Order is the pages'; the rows are the fresh ones. Re-sorting here
        // would move somebody under the reader's finger the moment they were
        // renamed, and the cursor the next page resumes from is the old order.
        people: repaged
            ? MemberPage(
                members: [
                  for (final member in _people.loaded.members)
                    byId[member.id] ?? member,
                ],
                hasMore: _people.loaded.hasMore,
              )
            : MemberPage(
                members: [
                  for (final member in state.people.members)
                    byId[member.id] ?? member,
                ],
                hasMore: state.people.hasMore,
              ),
        known: {
          for (final entry in state.known.entries)
            entry.key: byId[entry.key] ?? entry.value,
        },
      ),
    );
    // The permission cache on a `users` row is written by the same trigger
    // that a role change fires, so this runs on exactly the event that can
    // have moved somebody's roles.
    await _loadRoles([for (final member in refreshed) member.id], force: true);
    if (_countingRoles) await _countRoles();
    await _refreshExtras();
  }

  /// Whether a load that started as [loadId] is still the one we want.
  bool _stale(int loadId, String serverId) =>
      isClosed || loadId != _loadId || serverId != _watcher.serverId;

  /// Emit [next], and tell whoever is listening if our own moderation moved.
  void _emitLoaded(ServerMembersState next) {
    final previous = state;
    emit(next);
    _notifySelfModeration(previous, next);
  }

  /// A member's own mute/deafen state is baked into the LiveKit token they
  /// hold, which outlives the change by the best part of an hour. When ours
  /// moves, whoever is listening has to drop that token — otherwise a muted
  /// member gets their old permissions back just by rejoining.
  void _notifySelfModeration(
    ServerMembersState previous,
    ServerMembersState next,
  ) {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final myId = _session.serverById(serverId)?.user?.id;
    if (myId == null) return;

    // No prior row means this is the first load for the server, not a change.
    final before = previous.byId[myId];
    final after = next.byId[myId];
    if (before == null || after == null) return;

    if (before.isMuted != after.isMuted ||
        before.isDeafened != after.isDeafened) {
      _onSelfModerationChanged?.call();
    }
  }

  @override
  Future<void> close() async {
    for (final sub in _idSubs) {
      await sub.cancel();
    }
    await _watcher.dispose();
    return super.close();
  }
}
