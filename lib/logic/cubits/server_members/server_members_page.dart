part of 'server_members_cubit.dart';

/// What only the Members page reads: the banned list, and a search over the
/// whole roster, banned members included.
mixin _MembersPageMixin on Cubit<ServerMembersState>, _MembersRolesMixin {
  MembersApi _membersOn(String serverId);

  /// Whether the Members page is showing [ServerMembersState.banned].
  bool _showingBanned = false;

  /// Guards a slow search landing after a newer one, or after a clear.
  int _searchId = 0;

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
    final banned = await _membersOn(serverId).listBanned();
    if (banned == null || isClosed || serverId != _watcher.serverId) return;
    if (!_showingBanned) return;
    emit(state.copyWith(banned: banned));
    await _loadRoles([for (final member in banned) member.id]);
  }

  Future<void> _runSearch(String query, int id) async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final matches = await _membersOn(
      serverId,
    ).searchMembers(query: query, banned: null);
    if (isClosed || id != _searchId || serverId != _watcher.serverId) return;
    emit(state.copyWith(search: (query: query, matches: matches)));
    await _loadRoles([for (final member in matches) member.id]);
  }
}
