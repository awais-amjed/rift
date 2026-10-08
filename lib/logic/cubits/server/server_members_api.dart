part of 'server_cubit.dart';

/// Browsing the roster: a page of it, and every bot on it.
///
/// Split out of `_ServerApiMixin` because these share a shape the rest of that
/// file doesn't: they are the calls a dialog opens for a server other than the
/// one on screen (the rail's Manage members), so each one names its server and
/// the cache under them is keyed by server too.
///
/// **Nothing here returns the whole roster.** It used to — one call, every
/// member, and PostgREST silently cut the answer at 1000 rows, so every reader
/// was built on the assumption that a member absent from that list did not
/// exist. The member directory replaced it with bounded questions. This file holds the
/// browsing half; `_ServerMemberLookupApiMixin` holds the resolving half, which
/// is what lets a caller name somebody it never paged in.
mixin _ServerMembersApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  /// Implemented by [ServerCubit] — see its doc for why a named server never
  /// falls back to the selected one.
  Server? _target(String? serverId);
  String _noTarget(String? serverId);

  /// Held by [ServerCubit] because both member mixins write to it.
  List<ServerMember> _remember(String serverId, List<ServerMember> members);

  /// One alphabetical page of the roster.
  ///
  /// [after] is the previous page's [MemberPage.cursor]; null starts at the
  /// top. [channelId] narrows to members who can open that channel and answers
  /// a caller who cannot with nothing. [bots] and [banned] are tri-state — null
  /// for both, true for only those, false for only the others — and [banned]
  /// defaults to excluding them, because a banned member is not in the room.
  Future<({bool success, MemberPage? page, String? error})> listMembers({
    String? serverId,
    String? channelId,
    bool? bots,
    bool? banned = false,
    ({String name, String id})? after,
    int limit = MemberPage.pageSize,
  }) async {
    final server = _target(serverId);
    if (server == null) {
      return (success: false, page: null, error: _noTarget(serverId));
    }

    final response = await _callFor(
      server,
      (token) => _repository.listMembers(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        bots: bots,
        banned: banned,
        afterName: after?.name,
        afterId: after?.id,
        limit: limit,
      ),
    );
    if (!response.success) {
      return (
        success: false,
        page: null,
        error: response.error ?? 'Failed to load members',
      );
    }

    final data = response.data as Map<String, dynamic>;
    return (
      success: true,
      page: MemberPage(
        members: _remember(server.id, ServerMember.listFrom(response.data)),
        hasMore: data['has_more'] == true,
      ),
      error: null,
    );
  }

  /// Every bot on the server, or every bot a `/` command in [channelId] can
  /// reach, paged to exhaustion.
  ///
  /// The one place a whole list is still read, and it is safe for a reason that
  /// does not generalise to people: a bot is a program somebody registered and
  /// runs, so a server has a handful of them and not a population. The pickers
  /// that list them are choosing from all of them, and a picker that silently
  /// omitted one would be the bug this whole change is about.
  ///
  /// Still bounded. [_wholePageBudget] pages is far past any real server, and it
  /// is what stops this quietly becoming a full-table walk if somebody one day
  /// points it at people.
  Future<List<ServerMember>> listBots({
    String? serverId,
    String? channelId,
  }) async => (await _listWhole(
    serverId: serverId,
    channelId: channelId,
    bots: true,
  )).members;

  /// Every banned member, people and bots — the Members page's, which is the
  /// one place a ban can be lifted. Read whole for the reason bots are: a ban
  /// is somebody's deliberate act on one person, so there are few. Null when
  /// the read failed, which is not the same answer as nobody banned.
  Future<List<ServerMember>?> listBanned({String? serverId}) async {
    final read = await _listWhole(serverId: serverId, bots: null, banned: true);
    return read.failed ? null : read.members;
  }

  /// Every page of one filter of the roster, up to [_wholePageBudget], and
  /// whether a page failed on the way.
  Future<({List<ServerMember> members, bool failed})> _listWhole({
    String? serverId,
    String? channelId,
    bool? bots,
    bool? banned = false,
  }) async {
    final collected = <ServerMember>[];
    ({String name, String id})? after;

    for (var page = 0; page < _wholePageBudget; page++) {
      final result = await listMembers(
        serverId: serverId,
        channelId: channelId,
        bots: bots,
        banned: banned,
        after: after,
      );
      final fetched = result.page;
      if (fetched == null) return (members: collected, failed: true);
      collected.addAll(fetched.members);
      if (!fetched.hasMore || fetched.cursor == null) break;
      after = fetched.cursor;
    }
    return (members: collected, failed: false);
  }

  /// How many pages a whole read walks before it stops asking.
  static const int _wholePageBudget = 10;
}
