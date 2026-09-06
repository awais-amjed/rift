part of 'server_repository.dart';

/// Creating a server, reading everything about one, and changing its settings.
///
/// `create_server` and `update_server` are edge functions because they write
/// the LiveKit API secret into `server_secrets`, which has no grant and no
/// policy. `getServerDetails` is not: it is eleven ordinary reads under the
/// policies, and it is one call because a client that fetched channels, members
/// and limits separately would render three times on the way to being right.
mixin _ServerApiMixin {
  ServerDb get _db;

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// Create a new server. Returns server_id, name, supabase_url,
  /// supabase_key, and invite_code for the admin to register with.
  Future<APIResponse> createServer(
    String supabaseUrl, {
    required String serviceKey,
    required String name,
    String? iconUrl,
    required String livekitUrl,
    required String livekitApiKey,
    required String livekitSecretKey,
  }) {
    return _post(supabaseUrl, 'create_server', {
      'service_key': serviceKey,
      'name': name,
      'icon_url': iconUrl,
      'livekit_url': livekitUrl,
      'livekit_api_key': livekitApiKey,
      'livekit_secret_key': livekitSecretKey,
    });
  }

  /// Server metadata, its channels, and the caller's own profile row.
  ///
  /// Three selects rather than an endpoint that assembled them. `supabase_key`
  /// is echoed back from what the caller already had: it used to come from the
  /// server's environment, but by the time anyone can ask this question they
  /// are holding the key that let them ask.
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      // Our own row first, because it is the only one a banned member can
      // still read (`users_select_self`) and it decides whether the rest is
      // worth asking for.
      final user = await db
          .from('users')
          .select(
            'id, username, display_name, avatar_path, is_muted, is_deafened, '
            'is_banned, is_server_admin, is_channel_manager, can_create_tokens, '
            'is_owner',
          )
          .eq('id', ServerUserRow.uidOf(bearerToken) ?? '')
          .maybeSingle();

      // A ban makes `app.server_id()` null, so every other policy on the
      // server stops matching — including the one over `servers` itself. Read
      // in the old order that came back as "Server not found", the refresh
      // failed, and the client was left with stale channels and no idea why
      // nothing worked. It isn't missing; we are barred from it, which is the
      // one answer worth returning, and it is in the row we can still read.
      if (user != null && user['is_banned'] == true) {
        return {
          'supabase_key': anonKey,
          'channels': const <Map<String, dynamic>>[],
          'user': ServerUserRow.of(user),
        };
      }

      final server = await db
          .from('servers')
          .select('id, name, icon_url, livekit_url, $_limitColumns')
          .limit(1)
          .maybeSingle();
      if (server == null) {
        throw const PostgrestException(message: 'Server not found');
      }
      final channels = await db
          .from('channels')
          .select(
            'id, name, channel_type, retention_days, history_cap, is_private',
          )
          .order('name');

      // Best-effort: a server that predates 021 has no such function, and the
      // three cached booleans on the user row still answer the three questions
      // a client could ask before this existed.
      int bits = 0;
      try {
        bits = (await db.rpc('my_permissions') as num?)?.toInt() ?? 0;
      } catch (_) {}

      return {
        'server_id': server['id'],
        'name': server['name'],
        'icon_url': server['icon_url'],
        'livekit_url': server['livekit_url'],
        'supabase_key': anonKey,
        'channels': channels,
        'user': user == null
            ? null
            : ServerUserRow.withPermissionBits(ServerUserRow.of(user), bits),
        // Flat, so ServerLimits.fromJson reads this map and the
        // update_server response with the same code.
        ...ServerLimits.fromJson(server).toJson(),
      };
    });
  }

  /// The operator-limit columns added in migration 007, in the order
  /// [ServerLimits] reads them.
  static const _limitColumns =
      'max_attachment_bytes, message_retention_days, message_history_cap';

  /// Update server settings (admin only).
  ///
  /// One of the few things still on an edge function, and for the usual
  /// reason: it writes the LiveKit API key and secret. Those live in
  /// `server_secrets`, which has no client-reachable path at all, so the write
  /// has to happen somewhere holding the service role. Name, icon and the
  /// operator limits ride along rather than splitting one dialog across two
  /// transports — and the limits have a second reason to be here: saving the
  /// attachment cap also has to move the storage bucket's `file_size_limit`,
  /// which no client-reachable grant can do.
  Future<APIResponse> updateServer(
    String supabaseUrl, {
    String? bearerToken,
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
    ServerLimits? limits,
  }) {
    return _post(supabaseUrl, 'update_server', {
      'name': ?name,
      'icon_url': ?iconUrl,
      'livekit_url': ?livekitUrl,
      'livekit_api_key': ?livekitApiKey,
      'livekit_secret_key': ?livekitSecretKey,
      ...?limits?.toJson(),
    }, bearerToken: bearerToken);
  }

  /// Ask this server for a one-time token proving an admin wants it listed.
  ///
  /// Central owns the public directory and cannot tell who administers a
  /// server here — it has never heard of this database, and a member's
  /// identity here is unrelated to their Rift account. So the proof comes from
  /// the server itself: this returns a token that central redeems against this
  /// server's own domain before it will write a listing.
  ///
  /// Admin-gated at the endpoint. A member who is not one gets a refusal here
  /// rather than a listing they were never entitled to create.
  Future<APIResponse> listingToken(
    String supabaseUrl, {
    required String bearerToken,
  }) => _post(supabaseUrl, 'listing_token', const {}, bearerToken: bearerToken);
}
