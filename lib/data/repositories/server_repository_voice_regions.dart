part of 'server_repository.dart';

/// The LiveKit nodes a server may hold calls on.
///
/// Table calls, unlike everything in [_VoiceApiMixin] next door: a node is an
/// address and a label, and neither is a secret. The API key and secret are
/// the server's, shared by every node it has — a LiveKit key is a line in
/// each box's own `livekit.yaml`, written by the operator who is adding the
/// node here, so matching them is a setup step rather than something this has
/// to carry.
///
/// Who may write is `livekit_nodes_write_admins` and the matching update and
/// delete policies; this asks for no permission of its own.
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
          .select('id, label, url, is_default');
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
          .select('id, label, url, is_default');
      if ((rows as List).isEmpty) {
        throw const PostgrestException(
          message: 'Region not found, or not yours to change',
        );
      }
      return rows.first;
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
