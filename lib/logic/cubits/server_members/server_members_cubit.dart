import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/member_page.dart';
import '../../../data/classes/role.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_member.dart';
import '../../services/member_roster_pager.dart';
import '../../services/server_table_watcher.dart';
import '../server/server_cubit.dart';

part 'server_members_state.dart';

/// The selected server's members, kept live and kept bounded.
///
/// Presence (who is *online*) has always been realtime; membership (who is
/// *here at all*) was fetched once per server and cached until you switched
/// away, so somebody who joined while you were looking never appeared.
/// `users` is in the realtime publication for exactly this reason
/// (`004_realtime.sql`), and [ServerTableWatcher] turns a row event into a
/// refresh — which covers renames, new avatars, permission changes and bans as
/// well as joins.
///
/// **What changed with migration 039.** That refresh used to be three
/// full-table reads: every member, every role, every role assignment, on every
/// `users` row event. Somebody else changing their nickname cost the whole
/// roster, and the roster was silently cut at 1000 rows anyway. Now:
///
///  * bots are fetched whole, because there are a handful of them;
///  * people are paged alphabetically, as far as the sidebar is scrolled;
///  * anybody we hold an *id* for — presence, a call, a message author — is
///    resolved by id, which is bounded by who is actually about;
///  * a `users` event re-resolves only what is on screen, rather than
///    re-reading the server.
class ServerMembersCubit extends Cubit<ServerMembersState> {
  final ServerCubit _serverCubit;
  late final ServerTableWatcher _watcher;
  late final MemberRosterPager _people = MemberRosterPager(
    fetchPage: _fetchPeoplePage,
  );

  /// Guards against a slow fetch landing after a newer one, or after a switch.
  int _loadId = 0;

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

  ServerMembersCubit({required ServerCubit serverCubit})
    : _serverCubit = serverCubit,
      super(ServerMembersState()) {
    _watcher = ServerTableWatcher(
      serverCubit: serverCubit,
      table: 'users',
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
    final result = await _serverCubit.listMembers(bots: false, after: after);
    return result.page;
  }

  /// Everything the sidebar needs to draw its first frame: the bots, the first
  /// page of people, how many there are, and the roles behind the chips.
  Future<void> _loadFirst() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final loadId = ++_loadId;

    final bots = await _serverCubit.listBots();
    final counts = await _serverCubit.memberCounts();
    final roles = await _serverCubit.listRoles();
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
    await _loadRoles([...bots, ..._people.loaded.members]);
  }

  /// Page in more people — what the sidebar asks for as it is scrolled.
  Future<void> loadMorePeople() async {
    final serverId = _watcher.serverId;
    if (serverId == null || !await _people.next()) return;
    if (isClosed || serverId != _watcher.serverId) return;

    emit(state.copyWith(people: _people.loaded));
    await _loadRoles(_people.loaded.members);
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

    final found = await _serverCubit.membersByIds(wanted);
    if (isClosed || serverId != _watcher.serverId || found.isEmpty) return;

    _emitLoaded(
      state.copyWith(
        known: {...state.known, for (final member in found) member.id: member},
      ),
    );
    await _loadRoles(found);
  }

  /// Role chips for [members], merged into what is already known.
  ///
  /// Asked for the rows on screen rather than for the whole server:
  /// `member_role_list` is one row per (member, role), so reading it whole hit
  /// the response ceiling sooner than the roster itself did.
  Future<void> _loadRoles(List<ServerMember> members) async {
    final serverId = _watcher.serverId;
    final wanted = [
      for (final member in members)
        if (!state.memberRoles.containsKey(member.id)) member.id,
    ];
    if (serverId == null || wanted.isEmpty) return;

    final roles = await _serverCubit.memberRolesFor(wanted);
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
  /// pages — a name appearing in the middle of a list nobody has scrolled to is
  /// not a thing anyone can see anyway.
  Future<void> refresh() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    if (!state.loaded) return _loadFirst();
    final loadId = ++_loadId;

    final bots = await _serverCubit.listBots();
    final counts = await _serverCubit.memberCounts();
    final roles = await _serverCubit.listRoles();
    final refreshed = await _serverCubit.membersByIds(
      state.people.members.map((m) => m.id).toList(),
    );
    if (_stale(loadId, serverId)) return;

    final byId = {for (final member in refreshed) member.id: member};
    _emitLoaded(
      state.copyWith(
        bots: bots,
        peopleCount: counts.people,
        roles: roles,
        // Order is the pages'; the rows are the fresh ones. Re-sorting here
        // would move somebody under the reader's finger the moment they were
        // renamed, and the cursor the next page resumes from is the old order.
        people: MemberPage(
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
    // Whoever we already hold is re-resolved above; anybody in `known` who was
    // not in a page is refreshed on their next presence tick.
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
    final myId = _serverCubit.state.selectedServer?.user?.id;
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
