import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/services/paging.dart';
import '../classes/api_response.dart';
import '../classes/public_bot.dart';

/// The central bot directory — central's `public_bots` and `bot_likes`.
///
/// Runs over the same central Supabase client the server directory uses, with
/// the user's GoTrue session. Browsing and liking are policy-checked table
/// calls; publishing is the `publish_bot` RPC, which — unlike `publish_server`
/// — a member may call directly. A bot listing reserves nothing and names no
/// database, so there is nothing for an edge function to verify.
class PublicBotRepository {
  static const _table = 'public_bots';
  static const _likes = 'bot_likes';

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Browse the directory. [query] matches the name or the description,
  /// [tag] narrows to listings carrying it, [offset] pages.
  ///
  /// Answers `{results, has_more}`, over-fetching one row past the page so
  /// "there is more" is proved rather than guessed — [Paging.split], the same
  /// as the server browser.
  ///
  /// `is_listed` is filtered here as well as in the policy for the same reason
  /// it is there: the policy also shows you **your own** delisted rows, and a
  /// browser that showed those would be offering a bot nobody else can find.
  Future<APIResponse> browse({
    String? query,
    String? tag,
    BotSort sort = BotSort.top,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var request = _client.from(_table).select().eq('is_listed', true);

      final trimmed = query?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        final escaped = trimmed.replaceAll(RegExp(r'[%,()]'), ' ');
        request = request.or(
          'name.ilike.%$escaped%,description.ilike.%$escaped%',
        );
      }
      if (tag != null && tag.isNotEmpty) {
        request = request.contains('tags', [tag]);
      }

      // `created_at` breaks the tie rather than `updated_at`, matching
      // idx_public_bots_top: an author must not be able to lift an old bot up
      // the page by editing its description.
      var ordered = request.order(sort.column, ascending: false);
      if (sort != BotSort.fresh) {
        ordered = ordered.order('created_at', ascending: false);
      }
      final rows = await ordered.range(offset, offset + limit);

      final page = Paging.split(rows, limit: limit);
      final liked = await _likedAmong([for (final r in page.rows) r['id']]);

      return APIResponse.success({
        'results': [
          for (final r in page.rows)
            PublicBot.fromJson(r, likedByMe: liked.contains(r['id'])),
        ],
        'has_more': page.hasMore,
      });
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Which of [botIds] this account has already liked.
  ///
  /// One query for the page rather than a column on the listing, because
  /// "have *I* liked this" is per-reader and a listing is shared. Signed out,
  /// or asked about nothing, it is the empty set — a heart that is never
  /// filled in is the right answer then.
  Future<Set<String>> _likedAmong(List<dynamic> botIds) async {
    final uid = _uid;
    if (uid == null || botIds.isEmpty) return const {};
    try {
      final rows = await _client
          .from(_likes)
          .select('bot_id')
          .eq('user_id', uid)
          .inFilter('bot_id', botIds);
      return {for (final r in rows) r['bot_id'] as String};
    } catch (_) {
      // A directory that renders without hearts is worth more than one that
      // refuses to render.
      return const {};
    }
  }

  /// The caller's own listings, delisted ones included — the list the publish
  /// dialog manages, not the one the browser shows.
  Future<APIResponse> myListings() async {
    try {
      final uid = _uid;
      if (uid == null) return APIResponse.error('Not signed in.');

      final rows = await _client
          .from(_table)
          .select()
          .eq('owner_id', uid)
          .order('created_at', ascending: false);

      return APIResponse.success(
        rows.map((r) => PublicBot.fromJson(r)).toList(),
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Create ([id] null) or edit one of your own listings.
  ///
  /// Editing is by id rather than by name so a bot can be renamed: an upsert
  /// on the name would leave the old listing standing and spend another of
  /// the ten slots.
  Future<APIResponse> publish({
    String? id,
    required String name,
    required String sourceUrl,
    String? description,
    String? iconUrl,
    List<String> tags = const [],
    Map<String, dynamic>? manifest,
    bool isListed = true,
  }) async {
    try {
      final row = await _client.rpc(
        'publish_bot',
        params: {
          'p_id': id,
          'p_name': name,
          'p_source_url': sourceUrl,
          'p_description': description,
          'p_icon_url': iconUrl,
          'p_tags': tags,
          'p_manifest': manifest,
          'p_is_listed': isListed,
        },
      );
      return APIResponse.success(
        PublicBot.fromJson(row as Map<String, dynamic>),
      );
    } on PostgrestException catch (e) {
      final identifier = _identifierIn(e);
      return APIResponse.error(
        _messages[identifier] ?? e.message,
        errorCode: identifier,
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Withdraw a listing entirely. Delisting keeps the row; this doesn't, and
  /// the likes go with it.
  Future<APIResponse> remove(String botId) async {
    try {
      await _client.from(_table).delete().eq('id', botId);
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Like or unlike a bot.
  ///
  /// An insert and a delete rather than an RPC: there is no decision to make
  /// and no cap to enforce. The primary key is (bot_id, user_id), so liking
  /// twice is a duplicate key rather than two votes, and a trigger recounts
  /// `like_count` from the table either way — which is why the count this
  /// answers with is re-read rather than adjusted here.
  Future<APIResponse> setLiked(String botId, {required bool liked}) async {
    try {
      final uid = _uid;
      if (uid == null) return APIResponse.error('Not signed in.');

      if (liked) {
        await _client.from(_likes).insert({'bot_id': botId, 'user_id': uid});
      } else {
        await _client.from(_likes).delete().eq('bot_id', botId).eq(
          'user_id',
          uid,
        );
      }

      final row = await _client
          .from(_table)
          .select('like_count')
          .eq('id', botId)
          .maybeSingle();
      return APIResponse.success((row?['like_count'] as num?)?.toInt() ?? 0);
    } on PostgrestException catch (e) {
      // 23503 is the foreign key on `bot_likes.user_id`, which references the
      // profile table rather than `auth.users` — a bare sign-up is not a vote.
      // Its own sentence, not the one publishing uses: somebody tapping a
      // heart is not trying to list anything.
      if (e.code == '23503') return APIResponse.error(_likeNeedsProfile);
      // 23505 is liking twice, which two taps in a row can produce. It means
      // the like is already there, which is what was asked for.
      if (e.code == '23505') return APIResponse.success(null);
      return APIResponse.error(e.message);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// How many bots one account may list (`max_public_bots()`).
  Future<APIResponse> cap() async {
    try {
      final value = await _client.rpc('max_public_bots');
      return APIResponse.success((value as num).toInt());
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ── Errors ────────────────────────────────────────────────
  // The RPC raises bare identifiers. Turn the ones a person can act on into
  // sentences; anything else keeps the database's own words.

  /// Liking is the one write here an account can reach without meaning to
  /// publish anything, so the refusal says what it is refusing.
  static const _likeNeedsProfile =
      'Claim a handle on your Rift account before liking a bot.';

  static const _messages = {
    'owner_has_no_profile':
        'Claim a handle on your Rift account before listing a bot.',
    'listing_cap_reached':
        'You have listed as many bots as one account may. Remove one first.',
    'listing_not_yours':
        'That listing belongs to another account, so it cannot be edited here.',
  };

  /// Pull the raised identifier out of a Postgrest error.
  ///
  /// A `RAISE EXCEPTION 'listing_cap_reached'` arrives as the message, but a
  /// CHECK violation arrives as prose about a constraint, so anything that is
  /// not one of ours is left alone.
  static String _identifierIn(PostgrestException e) {
    final message = e.message.trim();
    return _messages.containsKey(message) ? message : 'unexpected_error';
  }
}
