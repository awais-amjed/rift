part of 'server_repository.dart';

/// Creating a server, reading everything about one, and changing its settings.
///
/// `create_server` and `update_server` are edge functions because they write
/// the LiveKit API secret into `server_secrets`, which has no grant and no
/// policy. `getServerDetails` is not: it is one RPC under the policies
/// (`get_server_details`, migration 022), because a client that fetched
/// channels, members and limits separately would render three times on the
/// way to being right — and, before 022, waited on five round trips to do it.
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

  /// Everything the client needs to draw this server, in one question.
  ///
  /// `get_server_details()` (migration 022). This used to be five or six
  /// selects run one after another — our own row, that row again for
  /// `is_owner`, the server, the channels, sometimes `channel_members`, and
  /// `my_permissions()` — none of which could start until the one before it
  /// came back. The client cannot draw any of it without all of it, so it was
  /// one question asked in six pieces, and every member of a server paid for
  /// all six again whenever anybody added a channel.
  ///
  /// The function is SECURITY INVOKER, so the same policies answer: the
  /// channels are the ones `channels_select` allows, and a banned member gets
  /// their own row with an empty channel list rather than "no such server" —
  /// a ban empties `app.server_id()`, which hides the `servers` row itself.
  ///
  /// Null means we have no row on this server at all: removed, or the server
  /// is gone. There is nothing left to refresh either way, and [ServerCubit]
  /// turns [ServerDb.serverGone] into dropping the rail chip.
  ///
  /// `supabase_key` is echoed back from what the caller already had, as
  /// before: by the time anyone can ask this question they are holding the
  /// key that let them ask.
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final data = await db.rpc('get_server_details');
      if (data is! Map) {
        throw const PostgrestException(message: ServerDb.serverGone);
      }
      return {
        ...Map<String, dynamic>.from(data),
        'supabase_key': anonKey,
      };
    });
  }

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
