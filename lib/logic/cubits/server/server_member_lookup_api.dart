part of 'server_cubit.dart';

/// Resolving members the client did not page in.
///
/// The other half of dropping the whole-roster read, and the half without which
/// dropping it would only move the bug. Once the client no longer holds every
/// member it still has *ids* in hand — from Realtime presence, from a message's
/// sender, from a voice room's participants — and *names* in hand, from the
/// `@`s somebody just typed. All of those used to be answered out of the
/// in-memory copy that is going away.
///
/// The cache lives on [ServerCubit] and every call here warms it, because its
/// job changed with the roster: it used to save a round trip on top of a list
/// we already had, and it is now the only record of somebody this client has
/// met. [findMember] falling through to [membersByIds] is what makes a name
/// resolvable at all for a member a thousand rows down the alphabet.
mixin _ServerMemberLookupApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  Server? _target(String? serverId);

  /// Held by [ServerCubit] because both member mixins read and write it.
  Map<String, Map<String, ServerMember>> get _memberCache;
  List<ServerMember> _remember(String serverId, List<ServerMember> members);

  /// A member by user id, from the cache or by asking for them by name.
  /// Null when they aren't a member of that server.
  Future<ServerMember?> findMember(String userId, {String? serverId}) async {
    final id = _target(serverId)?.id;
    if (id == null) return null;

    final cached = _memberCache[id]?[userId];
    if (cached != null) return cached;
    final found = await membersByIds([userId], serverId: id);
    return found.isEmpty ? null : found.first;
  }

  /// The best matches for [query], prefix matches first, capped.
  ///
  /// An empty query is the first alphabetical page, so a field can open on
  /// focus. A failure is an empty list: a search box is not the place to report
  /// that the server is unreachable, and every caller already draws "no
  /// matches" for the empty case.
  Future<List<ServerMember>> searchMembers({
    String? query,
    String? serverId,
    String? channelId,
    bool? bots,
    bool? banned = false,
    int limit = 25,
  }) async {
    final server = _target(serverId);
    if (server == null) return const [];

    final response = await _callFor(
      server,
      (token) => _repository.searchMembers(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        query: query,
        channelId: channelId,
        bots: bots,
        banned: banned,
        limit: limit,
      ),
    );
    if (!response.success) return const [];
    return _remember(server.id, ServerMember.listFrom(response.data));
  }

  /// How many ids go in one `members_by_ids` call.
  ///
  /// `app.member_page_max()` is what that function will return, and it *caps*
  /// rather than errors — so handing it more ids than this would silently
  /// answer about some of them and not the others, which is the exact failure
  /// this whole change exists to remove. Chunking is here rather than at each
  /// call site so that no caller can forget.
  static const int _idsPerCall = 100;

  /// Resolve ids the caller already holds — Realtime presence, a message's
  /// sender, a voice room's participants.
  Future<List<ServerMember>> membersByIds(
    List<String> ids, {
    String? serverId,
  }) async {
    final server = _target(serverId);
    if (server == null || ids.isEmpty) return const [];

    final found = <ServerMember>[];
    for (var start = 0; start < ids.length; start += _idsPerCall) {
      final end = start + _idsPerCall;
      final response = await _callFor(
        server,
        (token) => _repository.membersByIds(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
          ids: ids.sublist(start, end < ids.length ? end : ids.length),
        ),
      );
      if (!response.success) return const [];
      found.addAll(ServerMember.listFrom(response.data));
    }
    return _remember(server.id, found);
  }

  /// Resolve `@names` to the members a message in [channelId] can reach — the
  /// same set `validate_message_mentions` keeps.
  Future<List<ServerMember>> membersByUsernames(
    List<String> usernames, {
    String? channelId,
    String? serverId,
  }) async {
    final server = _target(serverId);
    if (server == null || usernames.isEmpty) return const [];

    final response = await _callFor(
      server,
      (token) => _repository.membersByUsernames(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        usernames: usernames,
        channelId: channelId,
      ),
    );
    if (!response.success) return const [];
    return _remember(server.id, ServerMember.listFrom(response.data));
  }

  /// How many people and how many bots are in scope, so a paged list can say
  /// how long it is rather than how far it has been scrolled.
  Future<({int people, int bots})> memberCounts({
    String? serverId,
    String? channelId,
  }) async {
    final server = _target(serverId);
    if (server == null) return (people: 0, bots: 0);

    final response = await _callFor(
      server,
      (token) => _repository.memberCounts(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
      ),
    );
    if (!response.success) return (people: 0, bots: 0);
    final data = response.data as Map<String, dynamic>;
    return (people: data['people'] as int, bots: data['bots'] as int);
  }
}
