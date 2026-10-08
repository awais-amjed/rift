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

part 'server_members_state.dart';

/// The selected server's members, kept live and kept bounded.
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
class ServerMembersCubit extends Cubit<ServerMembersState> {
  final SessionRepository _session;
  final MembersApi _members;
  final RolesApi _roles;
  late final ServerTopicWatcher _watcher;
  late final MemberRosterPager _people = MemberRosterPager(
    fetchPage: _fetchPeoplePage,
  );

  /// Guards against a slow fetch landing after a newer one, or after a switch.
  int _loadId = 0;

  /// Whether something is showing [ServerMembersState.roleCounts], so a
  /// refresh reads every assignment again rather than only the rows on screen.
  bool _countingRoles = false;

  /// Whether the Members page is showing [ServerMembersState.banned].
  bool _showingBanned = false;

  /// Guards a slow search landing after a newer one, or after a clear.
  int _searchId = 0;

  StreamSubscription<void>? _presenceSub;

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
  /// Wired from the outside rather than injected because [ChannelPresenceCubit]
  /// is built before this one, and reaching back for it would be a
  /// construction cycle.
  void watchPresence(Stream<Set<String>> onlineIds) {
    _presenceSub?.cancel();
    _presenceSub = onlineIds.listen((ids) => unawaited(resolve(ids)));
  }

  /// The selected server's members — the app's own — or, given [serverId],
  /// that one server's, for Manage server opened on a server the person is
  /// not looking at. Whoever opens that page owns that one and closes it.
  ServerMembersCubit({required SessionRepository session, String? serverId})
    : _session = session,
      _members = MembersApi(session: session),
      _roles = RolesApi(session: session),
      super(ServerMembersState()) {
    _watcher = ServerTopicWatcher(
      session: session,
      fixedServerId: serverId,
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
    final result = await _members.listMembers(
      serverId: _watcher.serverId,
      bots: false,
      after: after,
    );
    return result.page;
  }

  /// Everything the sidebar needs to draw its first frame: the bots, the first
  /// page of people, how many there are, and the roles behind the chips.
  Future<void> _loadFirst() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final loadId = ++_loadId;

    final bots = await _members.listBots(serverId: serverId);
    final counts = await _members.memberCounts(serverId: serverId);
    final roles = await _roles.listRoles(serverId: serverId);
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

    final found = await _members.membersByIds(wanted, serverId: serverId);
    if (isClosed || serverId != _watcher.serverId || found.isEmpty) return;

    _emitLoaded(
      state.copyWith(
        known: {...state.known, for (final member in found) member.id: member},
      ),
    );
    await _loadRoles([for (final member in found) member.id]);
  }

  /// Role chips for [userIds], merged into what is already known.
  ///
  /// Asked for the rows on screen rather than for the whole server:
  /// `member_role_list` is one row per (member, role), so reading it whole hit
  /// the response ceiling sooner than the roster itself did.
  ///
  /// [force] re-reads people already answered for. Paging leaves them alone —
  /// a page that has its chips does not need them again — but a refresh is
  /// here *because* something changed, and a role given or taken away is one
  /// of the things that changes. Without it the cache had no way of ever
  /// being wrong out loud: the chip stayed as it was first read until the
  /// server was switched.
  Future<void> _loadRoles(
    Iterable<String> userIds, {
    bool force = false,
  }) async {
    final serverId = _watcher.serverId;
    final wanted = [
      for (final id in userIds)
        if (force || !state.memberRoles.containsKey(id)) id,
    ];
    if (serverId == null || wanted.isEmpty) return;

    final roles = await _roles.memberRolesFor(wanted, serverId: serverId);
    if (isClosed || serverId != _watcher.serverId) return;
    emit(
      state.copyWith(
        memberRoles: {
          ...state.memberRoles,
          // Everybody asked about is recorded, holders and non-holders alike,
          // or the next page would ask about them all over again.
          for (final id in wanted) id: roles[id] ?? const [],
        },
      ),
    );
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

    final bots = await _members.listBots(serverId: serverId);
    final counts = await _members.memberCounts(serverId: serverId);
    final roles = await _roles.listRoles(serverId: serverId);

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
    final refreshed = await _members.membersByIds(
      {
        ...(repaged ? _people.loaded : state.people).members.map((m) => m.id),
        ...state.known.keys,
      }.toList(),
      serverId: serverId,
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

  // ── The Members page ────────────────────────────────────────

  /// Keep [ServerMembersState.banned] until [stopShowingBanned].
  Future<void> showBanned() async {
    _showingBanned = true;
    await _readBanned();
  }

  void stopShowingBanned() {
    _showingBanned = false;
    if (!isClosed && state.banned != null) {
      emit(state.copyWith(clearBanned: true));
    }
  }

  /// Answer [query] over the whole roster, banned members included — the
  /// Members page's search, where lifting a ban starts with finding the
  /// person. An empty query clears it.
  Future<void> search(String query) async {
    final id = ++_searchId;
    if (query.trim().isEmpty) {
      if (!isClosed) emit(state.copyWith(clearSearch: true));
      return;
    }
    await _runSearch(query, id);
  }

  /// What a refresh re-reads beyond the roster, when something shows it.
  Future<void> _refreshExtras() async {
    if (_showingBanned) await _readBanned();
    final asked = state.search?.query;
    if (asked != null) await _runSearch(asked, _searchId);
  }

  Future<void> _readBanned() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final banned = await _members.listBanned(serverId: serverId);
    if (banned == null || isClosed || serverId != _watcher.serverId) return;
    if (!_showingBanned) return;
    emit(state.copyWith(banned: banned));
    await _loadRoles([for (final member in banned) member.id]);
  }

  Future<void> _runSearch(String query, int id) async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final matches = await _members.searchMembers(
      query: query,
      serverId: serverId,
      banned: null,
    );
    if (isClosed || id != _searchId || serverId != _watcher.serverId) return;
    emit(state.copyWith(search: (query: query, matches: matches)));
    await _loadRoles([for (final member in matches) member.id]);
  }

  // ── Roles ───────────────────────────────────────────────────

  /// Keep [ServerMembersState.roleCounts] — what the Roles page shows beside
  /// each role — until [stopCountingRoles]. Every holder's roles land in
  /// [ServerMembersState.memberRoles] with it, the viewer's own among them,
  /// which is what decides how far down the ladder they reach.
  Future<void> countRoles() async {
    _countingRoles = true;
    await _countRoles();
  }

  /// Nothing is showing the counts any more; stop reading every assignment.
  void stopCountingRoles() {
    _countingRoles = false;
    if (!isClosed && state.roleCounts != null) {
      emit(state.copyWith(clearRoleCounts: true));
    }
  }

  /// Re-read the roles after this device changed one.
  ///
  /// A change to a role somebody holds rewrites their `users` row, and the
  /// doorbell that rings brings [refresh]. A role nobody holds moves no row —
  /// a new one always — so nothing rings for it, and without this the page
  /// that just made it would not show it.
  Future<void> refreshRoles() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final roles = await _roles.listRoles(serverId: serverId);
    if (isClosed || serverId != _watcher.serverId) return;
    if (roles.isNotEmpty) emit(state.copyWith(roles: roles));
    if (_countingRoles) await _countRoles();
  }

  /// Re-read which roles [userId] holds, after this device gave or took one.
  /// The doorbell would bring it too, a moment later; a checkbox the person
  /// just clicked should not wait for it.
  Future<void> reloadRolesOf(String userId) =>
      _loadRoles([userId], force: true);

  Future<void> _countRoles() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final held = await _roles.listMemberRoles(serverId: serverId);
    if (held == null || isClosed || serverId != _watcher.serverId) return;
    if (!_countingRoles) return;

    final counts = <String, int>{};
    for (final roles in held.values) {
      for (final role in roles) {
        counts[role.id] = (counts[role.id] ?? 0) + 1;
      }
    }
    emit(
      state.copyWith(
        // Every assignment on the server, so somebody absent holds nothing.
        memberRoles: {
          for (final id in state.memberRoles.keys) id: held[id] ?? const [],
          ...held,
        },
        roleCounts: counts,
      ),
    );
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
    await _presenceSub?.cancel();
    await _watcher.dispose();
    return super.close();
  }
}
