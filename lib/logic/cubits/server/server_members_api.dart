part of 'server_cubit.dart';

/// Browsing the roster: a page of it, every bot on it, and the one write that
/// changes what a member on it may do.
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

  /// [_noTarget] as the failed [APIResponse] the plain endpoints return.
  APIResponse _noTargetResponse(String? serverId) =>
      APIResponse.error(_noTarget(serverId));

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
  /// Still bounded. [_botPageBudget] pages is far past any real server, and it
  /// is what stops this quietly becoming a full-table walk if somebody one day
  /// points it at people.
  Future<List<ServerMember>> listBots({
    String? serverId,
    String? channelId,
  }) async {
    final collected = <ServerMember>[];
    ({String name, String id})? after;

    for (var page = 0; page < _botPageBudget; page++) {
      final result = await listMembers(
        serverId: serverId,
        channelId: channelId,
        bots: true,
        after: after,
      );
      final fetched = result.page;
      if (fetched == null) break;
      collected.addAll(fetched.members);
      if (!fetched.hasMore || fetched.cursor == null) break;
      after = fetched.cursor;
    }
    return collected;
  }

  /// How many pages [listBots] will walk before it stops asking.
  static const int _botPageBudget = 10;

  /// Persistently mutes/deafens/bans a user server-wide on [serverId], or on
  /// the selected server (requires channel manager or server admin).
  ///
  /// Omitted flags are left as they are — the endpoint reads the row back and
  /// reports the whole state, so a caller changing one thing never has to know
  /// the others.
  ///
  /// A ban is the persistent end of moderation: it removes them from every
  /// live call immediately and RLS refuses them everything afterwards. Setting
  /// [isBanned] false lets them back in; nothing else about them changed while
  /// they were out.
  Future<APIResponse> moderateUser({
    required String userId,
    bool? isMuted,
    bool? isDeafened,
    bool? isBanned,
    String? serverId,
  }) {
    final server = _target(serverId);
    if (server == null) return Future.value(_noTargetResponse(serverId));

    return _callFor(
      server,
      (token) => _repository.moderateUser(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        userId: userId,
        isMuted: isMuted,
        isDeafened: isDeafened,
        isBanned: isBanned,
      ),
    );
  }
}
