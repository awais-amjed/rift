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

  /// Servers, by address, that answered they have no `store_channel_keys`:
  /// older than self-host 077. Keys sealed for them go to the edge function
  /// until the app is next started.
  final Set<String> _keyWritesByEdgeFunction = {};

  /// The most a sweep pass sends at once: what the server hands out in one
  /// (`my_key_work`), and what `store_key_work` takes.
  static const _passEntries = 500;

  /// Store one channel's sealed keys.
  ///
  /// [SealedKeys.mint] is a new version: it fails with `keyring_conflict` if
  /// another writer got there first. Otherwise the version exists and this
  /// heals it, skipping anybody somebody else sealed meanwhile.
  ///
  /// One database call (`store_channel_keys`, self-host 077), which keeps the
  /// rules of the `post_channel_keys` edge function an older server is asked
  /// instead: seven to nine round trips to the database from there.
  Future<APIResponse> postChannelKeys(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required SealedKeys keys,
  }) async {
    if (!_keyWritesByEdgeFunction.contains(supabaseUrl)) {
      final response = await ServerDb.run(() async {
        final db = _db.client(supabaseUrl, anonKey, bearerToken);
        return db.rpc(
          'store_channel_keys',
          params: {
            'p_channel': keys.channelId,
            'p_version': keys.keyVersion,
            'p_entries': keys.entries,
            'p_mint': keys.mint,
            'p_link': keys.toJson()['link'],
          },
        );
      });
      if (response.errorCode != 'PGRST202') return response;
      _keyWritesByEdgeFunction.add(supabaseUrl);
    }
    return _post(
      supabaseUrl,
      'post_channel_keys',
      keys.toJson(),
      bearerToken: bearerToken,
    );
  }

  /// Store a sweep pass: `{results}`, one `{channel_id, key_version,
  /// success, code}` for each of [batches], in order.
  ///
  /// One database call a pass (`store_key_work`, self-host 077), where each
  /// channel was a request of its own. An older server is posted each batch
  /// in turn, as before. A pass bigger than the server takes is split.
  Future<APIResponse> storeKeyWork(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required List<SealedKeys> batches,
  }) async {
    final results = <Map<String, dynamic>>[];
    for (final pass in _passes(batches)) {
      if (!_keyWritesByEdgeFunction.contains(supabaseUrl)) {
        final response = await ServerDb.run(() async {
          final db = _db.client(supabaseUrl, anonKey, bearerToken);
          return db.rpc(
            'store_key_work',
            params: {
              'p_jobs': [for (final keys in pass) keys.toJson()],
            },
          );
        });
        if (response.errorCode != 'PGRST202') {
          if (!response.success) return response;
          results.addAll(
            ((response.data as Map<String, dynamic>)['results'] as List)
                .cast<Map<String, dynamic>>(),
          );
          continue;
        }
        _keyWritesByEdgeFunction.add(supabaseUrl);
      }
      for (final keys in pass) {
        final posted = await _post(
          supabaseUrl,
          'post_channel_keys',
          keys.toJson(),
          bearerToken: bearerToken,
        );
        // A sign-in the server no longer takes is the whole pass's: handed
        // back as itself, the session signs in again and sends it again.
        if (ErrorCode.isSessionInvalid(posted.errorCode)) return posted;
        results.add({
          'channel_id': keys.channelId,
          'key_version': keys.keyVersion,
          'success': posted.success,
          if (!posted.success) 'code': posted.errorCode,
        });
      }
    }
    return APIResponse.success({'results': results});
  }

  /// [batches] in runs of at most [_passEntries] entries, in order. A batch
  /// bigger than that goes alone, and the server refuses it.
  static List<List<SealedKeys>> _passes(List<SealedKeys> batches) {
    final passes = <List<SealedKeys>>[];
    var run = <SealedKeys>[];
    var size = 0;
    for (final keys in batches) {
      if (run.isNotEmpty && size + keys.entries.length > _passEntries) {
        passes.add(run);
        run = [];
        size = 0;
      }
      run.add(keys);
      size += keys.entries.length;
    }
    if (run.isNotEmpty) passes.add(run);
    return passes;
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
