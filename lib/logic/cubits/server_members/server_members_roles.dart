part of 'server_members_cubit.dart';

/// Who holds which role: the chips beside the members on screen, and the
/// counts the Roles page shows beside each role.
mixin _MembersRolesMixin on Cubit<ServerMembersState> {
  ServerTopicWatcher get _watcher;
  RolesApi _rolesOn(String serverId);

  /// Whether something is showing [ServerMembersState.roleCounts], so a
  /// refresh reads every assignment again rather than only the rows on screen.
  bool _countingRoles = false;

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

    final roles = await _rolesOn(serverId).memberRolesFor(wanted);
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
    final roles = await _rolesOn(serverId).listRoles();
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
    final held = await _rolesOn(serverId).listMemberRoles();
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
}
