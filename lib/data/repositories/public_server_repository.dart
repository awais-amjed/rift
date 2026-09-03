import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/services/paging.dart';
import '../classes/api_response.dart';
import '../classes/public_server.dart';

/// The central server directory (schema.md, `public_servers`).
///
/// Runs over the same central Supabase client the DM tier uses, with the user's
/// GoTrue session: browsing is a policy-checked read, publishing is the
/// `publish_server` RPC, and withdrawing is an own-row delete. Nothing here is
/// encrypted — a listing is meant to be read by strangers.
class PublicServerRepository {
  static const _table = 'public_servers';

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

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
  /// nobody else can find.
  Future<APIResponse> browse({
    String? query,
    String? tag,
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
  /// Through the RPC rather than an upsert for the reason `claim_handle`
  /// exists — there is no INSERT or UPDATE grant on the table at all, so the
  /// per-account cap and the ownership check can't be stepped around.
  Future<APIResponse> publish({
    required String supabaseUrl,
    required String serverId,
    required String inviteCode,
    required String name,
    String? description,
    String? iconUrl,
    List<String> tags = const [],
    int memberCount = 0,
    bool isListed = true,
  }) async {
    try {
      final row = await _client.rpc(
        'publish_server',
        params: {
          'p_supabase_url': supabaseUrl,
          'p_server_id': serverId,
          'p_invite_code': inviteCode,
          'p_name': name,
          'p_description': description,
          'p_icon_url': iconUrl,
          'p_tags': tags,
          'p_member_count': memberCount,
          'p_is_listed': isListed,
        },
      );
      return APIResponse.success(
        PublicServer.fromJson(row as Map<String, dynamic>),
      );
    } on PostgrestException catch (e) {
      return APIResponse.error(_explain(e), errorCode: _codeOf(e));
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
  // `publish_server` raises bare identifiers, which reach the client as a
  // Postgrest message. Turn the three a user can actually act on into
  // sentences; anything else keeps the server's own words.

  static const _messages = {
    'owner_has_no_profile':
        'Claim a handle on your Rift account before publishing a server.',
    'listing_owned_by_another_account':
        'This server is already listed by another account. Ask whoever '
        'published it to update or remove the listing.',
    'listing_cap_reached':
        'You have listed as many servers as one account may. Remove one first.',
  };

  static String? _codeOf(PostgrestException e) {
    for (final key in _messages.keys) {
      if (e.message.contains(key)) return key;
    }
    return e.code;
  }

  static String _explain(PostgrestException e) {
    final code = _codeOf(e);
    return _messages[code] ?? e.message;
  }
}
