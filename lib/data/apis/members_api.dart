import '../classes/member_page.dart';
import '../classes/server_member.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Over the repository budget and one job: reading a server's roster.
///
/// Reading the roster of a named server, or of the selected one: browsing it a
/// page at a time, and resolving members the client did not page in.
///
/// **Nothing here returns the whole roster.** It used to — one call, every
/// member, and PostgREST silently cut the answer at 1000 rows, so every reader
/// was built on the assumption that a member absent from that list did not
/// exist. The member directory replaced it with bounded questions.
///
/// Resolving is the half without which dropping the whole read would only
/// have moved the bug. The client still has *ids* in hand — from Realtime
/// presence, from a message's sender, from a voice room's participants — and
/// *names*, from the `@`s somebody just typed. Every read here warms
/// [SessionRepository.members], and [findMember] falling through to
/// [membersByIds] is what makes somebody a thousand rows down the alphabet
/// resolvable at all.
///
/// Holds nothing, so a widget builds one from the session.
class MembersApi {
  final SessionRepository _session;

  MembersApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  // ── Browsing ────────────────────────────────────────────

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
    final server = _session.target(serverId);
    if (server == null) {
      return (success: false, page: null, error: _session.noTarget(serverId));
    }

    final response = await _session.callFor(
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
        members: _session.members.remember(
          server.id,
          ServerMember.listFrom(response.data),
        ),
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

  // ── Resolving ───────────────────────────────────────────

  /// A member by user id, from the cache or by asking for them by name.
  /// Null when they aren't a member of that server.
  Future<ServerMember?> findMember(String userId, {String? serverId}) async {
    final id = _session.target(serverId)?.id;
    if (id == null) return null;

    final cached = _session.members.lookup(id, userId);
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
    final server = _session.target(serverId);
    if (server == null) return const [];

    final response = await _session.callFor(
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
    return _session.members.remember(
      server.id,
      ServerMember.listFrom(response.data),
    );
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
    final server = _session.target(serverId);
    if (server == null || ids.isEmpty) return const [];

    final found = <ServerMember>[];
    for (var start = 0; start < ids.length; start += _idsPerCall) {
      final end = start + _idsPerCall;
      final response = await _session.callFor(
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
    return _session.members.remember(server.id, found);
  }

  /// Resolve `@names` to the members a message in [channelId] can reach — the
  /// same set `validate_message_mentions` keeps.
  Future<List<ServerMember>> membersByUsernames(
    List<String> usernames, {
    String? channelId,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null || usernames.isEmpty) return const [];

    final response = await _session.callFor(
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
    return _session.members.remember(
      server.id,
      ServerMember.listFrom(response.data),
    );
  }

  /// How many people and how many bots are in scope, so a paged list can say
  /// how long it is rather than how far it has been scrolled.
  Future<({int people, int bots})> memberCounts({
    String? serverId,
    String? channelId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (people: 0, bots: 0);

    final response = await _session.callFor(
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
