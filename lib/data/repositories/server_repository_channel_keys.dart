part of 'server_repository.dart';

/// Channel keys: fetching the caller's sealed keys, finding key-distribution
/// work, and posting sealed entries for other members.
mixin _ChannelKeysApiMixin {
  ServerDb get _db;

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// Servers, by address, that answered they have no `my_channel_key`: older
  /// than self-host 063. Reads there go to the edge functions until the app
  /// is next started.
  final Set<String> _keysByEdgeFunction = {};

  /// Fetch my sealed channel keys + current version + members missing
  /// current-version entries (the healing set).
  ///
  /// One database call (`my_channel_key`, self-host 063). It answers what
  /// the `get_channel_key` edge function answers, which an older server is
  /// asked instead: that function made five round trips to the database
  /// (seven in a voice channel), and every channel open and voice join asked
  /// it.
  Future<APIResponse> getChannelKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
  }) => _keysRead(
    supabaseUrl,
    anonKey: anonKey,
    bearerToken: bearerToken,
    rpc: 'my_channel_key',
    params: {'p_channel': channelId},
    edgeFunction: 'get_channel_key',
    body: {'channel_id': channelId},
  );

  /// List every channel where the caller can do key-distribution work:
  /// `my_key_work`, or `sweep_channel_keys` on an older server, as
  /// [getChannelKey].
  Future<APIResponse> sweepChannelKeys(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) => _keysRead(
    supabaseUrl,
    anonKey: anonKey,
    bearerToken: bearerToken,
    rpc: 'my_key_work',
    params: const {},
    edgeFunction: 'sweep_channel_keys',
    body: const {},
  );

  /// [rpc], or [edgeFunction] where the server has no such call. The two
  /// answer in the same shape and refuse with the same codes.
  Future<APIResponse> _keysRead(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String rpc,
    required Map<String, dynamic> params,
    required String edgeFunction,
    required Map<String, dynamic> body,
  }) async {
    if (!_keysByEdgeFunction.contains(supabaseUrl)) {
      final response = await ServerDb.run(() async {
        final db = _db.client(supabaseUrl, anonKey, bearerToken);
        return db.rpc(rpc, params: params);
      });
      if (response.errorCode != 'PGRST202') return response;
      _keysByEdgeFunction.add(supabaseUrl);
    }
    return _post(supabaseUrl, edgeFunction, body, bearerToken: bearerToken);
  }

  // An edge function on the service role: it enforces the "current + 1"
  // version race.

  /// Store sealed keyring entries for [keyVersion].
  ///
  /// [mint] is a new version: it fails with `keyring_conflict` if another
  /// writer got there first. Otherwise the version exists and this heals it,
  /// skipping anybody somebody else sealed meanwhile.
  Future<APIResponse> postChannelKeys(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
    required bool mint,
    ({String ciphertext, String nonce})? link,
  }) {
    return _post(supabaseUrl, 'post_channel_keys', {
      'channel_id': channelId,
      'key_version': keyVersion,
      'entries': entries,
      'mint': mint,
      if (link != null)
        'link': {'ciphertext': link.ciphertext, 'nonce': link.nonce},
    }, bearerToken: bearerToken);
  }

  /// Drop this member's own keyring rows at [versions], which the channel's
  /// links already open from a newer row they keep. An RPC rather than an
  /// edge function: it touches only the caller's rows, and the server checks
  /// the chain is there (`prune_channel_keys`).
  Future<APIResponse> pruneChannelKeys(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required List<int> versions,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'prune_channel_keys',
        params: {'p_channel': channelId, 'p_versions': versions},
      );
    });
  }
}
