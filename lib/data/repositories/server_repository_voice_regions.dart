part of 'server_repository.dart';

/// The LiveKit nodes a server may hold calls on.
///
/// Table calls, unlike everything in [_VoiceApiMixin] next door: a node is an
/// address and a label, and neither is a secret. Who may write is
/// `livekit_nodes_write_admins` and the matching update and delete policies;
/// these ask for no permission of their own.
///
/// [setVoiceRegionCredentials] is the exception and is an RPC, because a
/// region's own key pair lives in a table with no policy and no grant. It
/// checks the caller itself — see the function in migration 003.
mixin _VoiceRegionsMixin {
  ServerDb get _db;

  /// Add a node. The label is what a channel manager picks from, so it is a
  /// place rather than a hostname.
  Future<APIResponse> addVoiceRegion(
    String supabaseUrl, {
    required String serverId,
    required String label,
    required String url,
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final rows = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('livekit_nodes')
          .insert({'server_id': serverId, 'label': label, 'url': url})
          .select('id, label, url, is_default, has_own_key');
      return (rows as List).first;
    });
  }

  Future<APIResponse> updateVoiceRegion(
    String supabaseUrl,
    String nodeId, {
    String? label,
    String? url,
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final patch = <String, dynamic>{'label': ?label, 'url': ?url};
      if (patch.isEmpty) {
        throw const PostgrestException(message: 'Nothing to update');
      }
      final rows = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('livekit_nodes')
          .update(patch)
          .eq('id', nodeId)
          .select('id, label, url, is_default, has_own_key');
      if ((rows as List).isEmpty) {
        throw const PostgrestException(
          message: 'Region not found, or not yours to change',
        );
      }
      return rows.first;
    });
  }

  /// Give a region its own LiveKit key pair, or take it back.
  ///
  /// Both null clears the row, which puts the region on the server's pair —
  /// the same state as a region that never had one. Nothing comes back: the
  /// key is write-only from here, and the flag saying a region has one rides
  /// on the node row with everything else.
  Future<APIResponse> setVoiceRegionCredentials(
    String supabaseUrl,
    String nodeId, {
    String? apiKey,
    String? secret,
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'set_voice_region_credentials',
            params: {
              'p_node': nodeId,
              'p_api_key': apiKey,
              'p_secret': secret,
            },
          );
      return null;
    });
  }

  /// Remove a node. Channels pinned to it go back to automatic, and a call
  /// running on it keeps running — nothing here reaches LiveKit.
  ///
  /// The default node refuses, from a trigger, because it is the server's own
  /// `livekit_url` under another name: deleting it would leave that column
  /// naming an address absent from the list.
  Future<APIResponse> deleteVoiceRegion(
    String supabaseUrl,
    String nodeId, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('livekit_nodes')
          .delete()
          .eq('id', nodeId);
      return null;
    });
  }
}
