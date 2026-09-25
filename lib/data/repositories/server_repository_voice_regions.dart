part of 'server_repository.dart';

/// The LiveKit nodes a server may hold calls on.
///
/// Renaming, repointing and removing are table calls, under
/// `livekit_nodes_update_admins` and the matching delete policy; they ask for
/// no permission of their own.
///
/// **Adding is an RPC**, because a region and the key it signs with are one
/// act: every added region carries its own pair, in a table with no policy
/// and no grant, and a node written without one would fall back to the
/// server's key — which is the thing per-region keys exist to prevent. The
/// function writes both rows in one transaction and checks the caller itself;
/// there is no client INSERT on `livekit_nodes` at all.
mixin _VoiceRegionsMixin {
  ServerDb get _db;

  /// Add a node, with the key pair it signs with. The label is what a channel
  /// manager picks from, so it is a place rather than a hostname.
  Future<APIResponse> addVoiceRegion(
    String supabaseUrl, {
    required String label,
    required String url,
    required String apiKey,
    required String secret,
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      return await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'add_voice_region',
            params: {
              'p_label': label,
              'p_url': url,
              'p_api_key': apiKey,
              'p_secret': secret,
            },
          );
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
          .select('id, label, url, is_default');
      if ((rows as List).isEmpty) {
        throw const PostgrestException(
          message: 'Region not found, or not yours to change',
        );
      }
      return rows.first;
    });
  }

  /// Replace a region's key pair — a rotation, one box at a time.
  ///
  /// Both halves, always: there is no giving a region's key up, because a
  /// region without one would run on the server's. Nothing comes back, the
  /// key being write-only from here.
  Future<APIResponse> setVoiceRegionCredentials(
    String supabaseUrl,
    String nodeId, {
    required String apiKey,
    required String secret,
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
