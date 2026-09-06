part of 'server_repository.dart';

/// The member directory (`011_directory.sql`) — the roster a page at a time, and the
/// lookups that replace holding all of it.
///
/// Split from `_AuthApiMixin`, which used to hold the one call this file
/// replaces. `listUsers` was `SELECT … FROM users` with no limit, and PostgREST
/// caps a response at 1000 rows: a bigger server's members were not missing,
/// they were *silently* missing, in the sidebar and the `@` menu and mention
/// resolution alike. Six bounded questions in a file of their own is what stops
/// the seventh caller reaching for the whole table again.
///
/// Every one of these is an RPC rather than a table read. A table read with a
/// `.limit()` would have raised the same ceiling, but the interesting filters —
/// who can open this channel, is this a bot, is this member banned — belong
/// with `app.channel_eligible` and not in a PostgREST query string assembled
/// twelve different ways.
mixin _MemberApiMixin {
  ServerDb get _db;

  /// Rows from any member RPC, in the shape the client models expect.
  static List<Map<String, dynamic>> _members(dynamic rows) => [
    for (final u in (rows as List).cast<Map<String, dynamic>>())
      ServerUserRow.of(u),
  ];

  /// One alphabetical page of the roster.
  ///
  /// [afterName] and [afterId] are the previous page's last row — keyset
  /// paging, not an offset, because the sidebar pages while people are joining
  /// and renaming themselves and a shifting sort under an offset skips and
  /// repeats rows at every boundary.
  ///
  /// [channelId] restricts to members who can open that channel and answers a
  /// caller who cannot with nothing. [bots] and [banned] are tri-state: null
  /// for both, true for only those, false for only the others.
  Future<APIResponse> listMembers(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    String? channelId,
    bool? bots,
    bool? banned = false,
    String? afterName,
    String? afterId,
    int limit = MemberPage.pageSize,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db.rpc(
        'list_members',
        params: {
          'p_channel': channelId,
          'p_bots': bots,
          'p_banned': banned,
          'p_after_name': afterName,
          'p_after_id': afterId,
          // One row past the page — see Paging.split.
          'p_limit': limit + 1,
        },
      );
      final page = Paging.split(_members(rows), limit: limit);
      return {'users': page.rows, 'has_more': page.hasMore};
    });
  }

  /// The best matches for [query], prefix matches first.
  ///
  /// An empty query is the first alphabetical page, which is what lets a search
  /// field open on focus without a second round trip. Ranked, so not paged:
  /// this feeds typeaheads, which show a handful of rows and narrow as you keep
  /// typing.
  Future<APIResponse> searchMembers(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    String? query,
    String? channelId,
    bool? bots,
    bool? banned = false,
    int limit = 25,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db.rpc(
        'search_members',
        params: {
          'p_query': query,
          'p_channel': channelId,
          'p_bots': bots,
          'p_banned': banned,
          'p_limit': limit,
        },
      );
      return {'users': _members(rows)};
    });
  }

  /// Resolve ids the caller already holds — Realtime presence, a message's
  /// sender, a voice room's participants.
  ///
  /// This and [membersByUsernames] are what make dropping the whole-roster read
  /// possible rather than merely smaller: both questions used to be answered
  /// out of the in-memory copy that is going away.
  Future<APIResponse> membersByIds(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required List<String> ids,
  }) {
    return ServerDb.run(() async {
      if (ids.isEmpty) return {'users': <Map<String, dynamic>>[]};
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db.rpc('members_by_ids', params: {'p_ids': ids});
      return {'users': _members(rows)};
    });
  }

  /// Resolve `@names` to the members a message in [channelId] can reach.
  ///
  /// Channel-scoped because that is the question: `validate_message_mentions`
  /// strips an id that cannot open the channel, so a composer resolving a name
  /// the trigger then drops would show a ping that never happened.
  Future<APIResponse> membersByUsernames(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required List<String> usernames,
    String? channelId,
  }) {
    return ServerDb.run(() async {
      if (usernames.isEmpty) return {'users': <Map<String, dynamic>>[]};
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db.rpc(
        'members_by_usernames',
        params: {'p_names': usernames, 'p_channel': channelId},
      );
      return {'users': _members(rows)};
    });
  }

  /// How many people and how many bots are in scope, so a paged list can say
  /// how long it is rather than how far you have scrolled.
  Future<APIResponse> memberCounts(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    String? channelId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final row = await db.rpc(
        'member_counts',
        params: {'p_channel': channelId},
      );
      final counts = (row as Map<String, dynamic>?) ?? const {};
      return {
        'people': (counts['people'] as num?)?.toInt() ?? 0,
        'bots': (counts['bots'] as num?)?.toInt() ?? 0,
      };
    });
  }

  /// Which roles these members hold, most senior first — the chips for the rows
  /// on screen rather than for everybody.
  ///
  /// `member_role_list` is one row per (member, role), so reading it whole hit
  /// the response ceiling sooner than the roster itself did.
  Future<APIResponse> memberRolesFor(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required List<String> ids,
  }) {
    return ServerDb.run(() async {
      if (ids.isEmpty) return {'assignments': <Map<String, dynamic>>[]};
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db.rpc('member_roles_for', params: {'p_ids': ids});
      return {'assignments': rows};
    });
  }
}
