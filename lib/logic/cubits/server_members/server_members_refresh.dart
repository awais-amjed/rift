part of 'server_members_cubit.dart';

/// Answering a `members` ring: re-reading the members this list holds that
/// the ring named, or every one of them when it named nobody.
mixin _MembersRefreshMixin
    on Cubit<ServerMembersState>, _MembersRolesMixin, _MembersPageMixin {
  MemberRosterPager get _people;
  int get _loadId;
  set _loadId(int value);
  Future<void> _loadFirst();
  bool _stale(int loadId, String serverId);
  void _emitLoaded(ServerMembersState next);

  /// This server answered that it has no `members_refresh`, so a ring is
  /// answered with the separate requests until the server is next set up.
  bool _noRefreshCall = false;

  /// A `users` row changed, or who holds which role. Re-read what is on
  /// screen, and nothing else.
  ///
  /// [named] is who the ring said moved; null when it named nobody (a role's
  /// name or colour, a change to many, the topic opening again), and then
  /// everybody held is read again. A ring about somebody not held still
  /// reads the counts, the roles and the bots, which is how a join shows up:
  /// through [ServerMembersState.peopleCount] and, once somebody scrolls to
  /// them, through the pages — except when every page is already loaded,
  /// where there is nothing left to scroll to, so the roster is read again
  /// from the top.
  Future<void> refresh({Set<String>? named}) async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    if (!state.loaded) return _loadFirst();
    final loadId = ++_loadId;

    // Everybody we hold, paged or resolved by id: somebody known only from a
    // call or a message kept their old name and picture until they left.
    final held = {
      ...state.people.members.map((m) => m.id),
      ...state.known.keys,
    };
    final wanted = (named == null ? held : held.intersection(named)).toList();

    final read = _noRefreshCall
        ? null
        : await _membersOn(
            serverId,
          ).refresh(wanted.take(MembersApi.idsPerRefresh).toList());
    if (_stale(loadId, serverId)) return;
    if (read == null || read.unsupported) {
      _noRefreshCall = true;
      return _refreshOneByOne(serverId, loadId, wanted);
    }
    // A failed read leaves what is on screen.
    final fresh = read.read;
    if (fresh == null) return;

    // A bot is somebody's program, so a page of them is already past any real
    // server, but the list is meant to be whole.
    final bots = fresh.bots.hasMore
        ? await _membersOn(serverId).listBots()
        : fresh.bots.members;
    if (_stale(loadId, serverId)) return;
    final repaged = await _repageIfMoved(serverId, loadId, fresh.peopleCount);
    if (repaged == null) return;

    // Past what one call answers, one by one as before.
    final rest = wanted.skip(MembersApi.idsPerRefresh).toList();
    final more = rest.isEmpty
        ? const <ServerMember>[]
        : await _membersOn(serverId).membersByIds(rest);
    if (_stale(loadId, serverId)) return;

    final asked = [
      ...wanted.take(MembersApi.idsPerRefresh),
      for (final bot in fresh.bots.members) bot.id,
    ];
    _emitLoaded(
      _withFresh(
        {
          for (final member in [...fresh.members, ...more]) member.id: member,
        },
        bots: bots,
        peopleCount: fresh.peopleCount,
        roles: fresh.roles,
        repaged: repaged,
      ).copyWith(
        memberRoles: {
          ...state.memberRoles,
          // Holders and non-holders alike, as `_loadRoles` records them.
          for (final id in asked) id: fresh.memberRoles[id] ?? const [],
        },
      ),
    );
    if (rest.isNotEmpty) await _loadRoles(rest, force: true);
    await _afterRefresh(repaged);
  }

  /// [refresh] on a server older than `members_refresh`: the bots, the
  /// counts and the roles at once, then the members held, then their chips.
  Future<void> _refreshOneByOne(
    String serverId,
    int loadId,
    List<String> wanted,
  ) async {
    final (bots, counts, roles) = await (
      _membersOn(serverId).listBots(),
      _membersOn(serverId).memberCounts(),
      _rolesOn(serverId).listRoles(),
    ).wait;
    if (_stale(loadId, serverId)) return;
    final repaged = await _repageIfMoved(serverId, loadId, counts.people);
    if (repaged == null) return;

    final refreshed = await _membersOn(serverId).membersByIds(wanted);
    if (_stale(loadId, serverId)) return;

    _emitLoaded(
      _withFresh(
        {for (final member in refreshed) member.id: member},
        bots: bots,
        peopleCount: counts.people,
        roles: roles,
        repaged: repaged,
      ),
    );
    // A role given or taken away is one of the things a ring is about, so
    // the chips of everybody re-read are read again too.
    await _loadRoles([for (final member in refreshed) member.id], force: true);
    await _afterRefresh(repaged);
  }

  /// With every page loaded and the count moved, read the roster again from
  /// the top, as far as it was, so a join or a ban lands. Whether it did, or
  /// null when the read is no longer wanted.
  Future<bool?> _repageIfMoved(
    String serverId,
    int loadId,
    int peopleCount,
  ) async {
    if (state.people.hasMore || peopleCount == state.people.members.length) {
      return false;
    }
    final reach = state.people.members.length;
    _people.reset();
    while (await _people.next() &&
        _people.loaded.members.length < reach &&
        _people.hasMore) {}
    if (_stale(loadId, serverId)) return null;
    // A read that failed part way leaves what was on screen, not nothing.
    return _people.loaded.members.isNotEmpty || peopleCount == 0;
  }

  /// The state with the fresh rows put in place.
  ///
  /// Order is the pages'; the rows are the fresh ones. Re-sorting here would
  /// move somebody under the reader's finger the moment they were renamed,
  /// and the cursor the next page resumes from is the old order.
  ServerMembersState _withFresh(
    Map<String, ServerMember> byId, {
    required List<ServerMember> bots,
    required int peopleCount,
    required List<Role> roles,
    required bool repaged,
  }) {
    final page = repaged ? _people.loaded : state.people;
    return state.copyWith(
      bots: bots,
      peopleCount: peopleCount,
      // Every server has its baseline role, so none back means the read
      // failed — keep the ladder on screen rather than blanking it.
      roles: roles.isEmpty ? null : roles,
      people: MemberPage(
        members: [for (final member in page.members) byId[member.id] ?? member],
        hasMore: page.hasMore,
      ),
      known: {
        for (final entry in state.known.entries)
          entry.key: byId[entry.key] ?? entry.value,
      },
    );
  }

  /// What follows either way: chips for whoever the pages brought in, the
  /// Roles page's counts, and the Members page's lists.
  Future<void> _afterRefresh(bool repaged) async {
    if (repaged) {
      await _loadRoles([
        for (final member in _people.loaded.members) member.id,
      ]);
    }
    if (_countingRoles) await _countRoles();
    await _refreshExtras();
  }
}
