import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/services/paging.dart';
import '../classes/api_response.dart';
import '../classes/public_server.dart';

/// The central server directory — central's `public_servers` table.
///
/// Runs over the same central Supabase client the DM tier uses, with the user's
/// GoTrue session: browsing is a policy-checked read, publishing is the
/// `publish_server` RPC, and withdrawing is an own-row delete. Nothing here is
/// encrypted — a listing is meant to be read by strangers.
class PublicServerRepository {
  static const _table = 'public_servers';

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  /// The signed-in central account, so a listing's own publisher is not
  /// offered a Report button on it.
  String? get currentUserId => _uid;

  /// Browse the directory. [query] matches the name or the description,
  /// [tag] narrows to listings carrying it, [offset] pages.
  ///
  /// Answers `{results, has_more}`. Over-fetches one row past the page so
  /// "there is more" is proved rather than guessed from a full page — see
  /// [Paging.split]. The directory used to be read as one page of 50 with no
  /// way to ask for the next, which meant the 51st listed server could not be
  /// found at all and nothing on screen said so.
  ///
  /// `is_listed` is filtered here as well as in the policy, which reads as
  /// redundant and isn't: the policy also lets you see **your own** delisted
  /// rows, and a browser that showed those would be showing you a server
  /// nobody else can find. `hidden_at` the same: the policy shows a hidden
  /// listing to its owner, and to a moderator, and to nobody browsing.
  Future<APIResponse> browse({
    String? query,
    String? tag,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var request = _client
          .from(_table)
          .select()
          .eq('is_listed', true)
          .isFilter('hidden_at', null);

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

      final rows = await request
          .order('member_count', ascending: false)
          .order('updated_at', ascending: false)
          .range(offset, offset + limit);

      final page = Paging.split(rows, limit: limit);
      return APIResponse.success({
        'results': [for (final r in page.rows) PublicServer.fromJson(r)],
        'has_more': page.hasMore,
      });
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// The caller's own listings, delisted ones included — this is the list the
  /// publish dialog manages, not the one the browser shows.
  /// Whether anybody has listed [serverId] at [supabaseUrl], whoever that
  /// was. Only a listed row is visible to somebody other than its publisher,
  /// so a `false` here means "not findable", which is the question asked.
  Future<APIResponse> isListed({
    required String supabaseUrl,
    required String serverId,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .select('id')
          .eq('supabase_url', supabaseUrl)
          .eq('server_id', serverId)
          .eq('is_listed', true)
          .isFilter('hidden_at', null)
          .maybeSingle();
      return APIResponse.success(row != null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  Future<APIResponse> myListings() async {
    try {
      final uid = _uid;
      if (uid == null) return APIResponse.error('Not signed in.');

      final rows = await _client
          .from(_table)
          .select()
          .eq('owner_id', uid)
          .order('updated_at', ascending: false);

      return APIResponse.success(
        rows.map((r) => PublicServer.fromJson(r)).toList(),
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// The one listing for a given server, or success(null) when it has never
  /// been published — including when someone else published it, since the
  /// select policy hides a delisted row that isn't yours.
  Future<APIResponse> listingFor({
    required String supabaseUrl,
    required String serverId,
  }) async {
    try {
      final row = await _client
          .from(_table)
          .select()
          .eq('supabase_url', supabaseUrl)
          .eq('server_id', serverId)
          .maybeSingle();

      return APIResponse.success(
        row == null ? null : PublicServer.fromJson(row),
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Create or update the listing for one server.
  ///
  /// Through the **edge function**, not the RPC, and that is the whole
  /// security of the directory. Central cannot tell who administers a
  /// self-hosted server: it has never heard of that database, and a member's
  /// identity there is unrelated to their Rift account. So the RPC used to
  /// check only that the caller was signed in here — and every *member* of a
  /// server holds its URL, its id and an invite code, which was everything
  /// needed to list somebody else's server, permanently, with a working join
  /// link and a description of their choosing.
  ///
  /// [listingToken] comes from the server being listed (`ServerCubit
  /// .listingToken`, admin-gated there), and central redeems it against that
  /// server's own domain before writing anything. The RPC is now service-role
  /// only, so this path cannot be gone around.
  Future<APIResponse> publish({
    required String supabaseUrl,
    required String serverId,
    required String inviteCode,
    required String name,
    required String listingToken,
    String? description,
    String? iconPath,
    List<String> tags = const [],
    int memberCount = 0,
    bool isListed = true,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'publish_server',
        body: {
          'supabase_url': supabaseUrl,
          'server_id': serverId,
          'invite_code': inviteCode,
          'name': name,
          'listing_token': listingToken,
          'description': description,
          'icon_path': iconPath,
          'tags': tags,
          'member_count': memberCount,
          'is_listed': isListed,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data['error'] != null) {
        return APIResponse.error(
          _explainIdentifier('${data['error']}'),
          errorCode: '${data['error']}',
        );
      }
      return APIResponse.success(
        PublicServer.fromJson(data as Map<String, dynamic>),
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      final identifier = detail is Map && detail['error'] != null
          ? '${detail['error']}'
          : 'unexpected_error';
      return APIResponse.error(
        _explainIdentifier(identifier),
        errorCode: identifier,
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Withdraw a listing entirely. Delisting keeps the row; this doesn't.
  Future<APIResponse> remove(String listingId) async {
    try {
      await _client.from(_table).delete().eq('id', listingId);
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// How many servers one account may list (`max_public_servers()`).
  Future<APIResponse> cap() async {
    try {
      final value = await _client.rpc('max_public_servers');
      return APIResponse.success((value as num).toInt());
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ── Errors ────────────────────────────────────────────────
  // Both the RPC and the edge function answer with bare identifiers. Turn the
  // ones a person can act on into sentences; anything else keeps the server's
  // own words.

  static const _messages = {
    'owner_has_no_profile':
        'Claim a handle on your Rift account before publishing a server.',
    'listing_owned_by_another_account':
        'This server is already listed by another account. Ask whoever '
        'published it to update or remove the listing.',
    'publisher_banned':
        'Rift moderators have stopped this account listing servers in the '
        'directory.',
    'listing_cap_reached':
        'You have listed as many servers as one account may. Remove one first.',
    // The three the proof round trip can produce. Each is actionable, and
    // none of them says anything about what central found at the address.
    'listing_not_authorised':
        'Your server did not confirm this listing. Only a server admin can '
        'publish it, and the confirmation expires after a few minutes — try '
        'again.',
    'server_unreachable':
        'Your server did not answer, so the listing was not published. Try '
        'again once it is back online.',
    'server_url_not_allowed':
        'A listed server has to be reachable at an https address of its own. '
        'A local or private address cannot be published.',
  };

  /// The sentence for an identifier, or the identifier itself.
  ///
  /// Publishing goes through the edge function now, so these arrive as plain
  /// strings rather than wrapped in a Postgrest message — the two helpers that
  /// unwrapped one went with the RPC call that produced it.
  static String _explainIdentifier(String identifier) =>
      _messages[identifier] ?? identifier;
}
