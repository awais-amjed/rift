import '../classes/api_response.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Adding, renaming and removing the LiveKit nodes the selected server holds
/// calls on.
///
/// All of them end the same way — the server re-read, so the node list and
/// every channel's pin come back in step — which is the seam this shares with
/// `ChannelsApi` and the reason it is its own class rather than more methods
/// on `VoiceApi`.
///
/// The probe's cached measurement is thrown away on every change: it is keyed
/// on the set of nodes, so an added or removed one has to be measured before
/// the next call can be sent anywhere sensible.
///
/// The default region's address and key are the *server's*, written through
/// `update_server`, so changing those is `ServerApi.updateDefaultVoiceRegion`.
///
/// Holds nothing, so a widget builds one from the session.
class VoiceRegionsApi {
  final SessionRepository _session;

  VoiceRegionsApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// Adds a region, with the LiveKit key pair it signs with — both required,
  /// because a region without one would fall back to the server's key.
  Future<({bool success, String? error})> addVoiceRegion({
    required String label,
    required String url,
    required String apiKey,
    required String secret,
  }) => _change(
    (server, token) => _repository.addVoiceRegion(
      server.supabaseUrl,
      label: label,
      url: url,
      apiKey: apiKey,
      secret: secret,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
    failure: 'Failed to add the region',
  );

  Future<({bool success, String? error})> updateVoiceRegion({
    required String nodeId,
    String? label,
    String? url,
  }) => _change(
    (server, token) => _repository.updateVoiceRegion(
      server.supabaseUrl,
      nodeId,
      label: label,
      url: url,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
    failure: 'Failed to change the region',
  );

  /// Replaces the key pair a region signs with — a rotation, one box at a
  /// time.
  ///
  /// Its own call rather than part of [updateVoiceRegion], because it writes a
  /// different table through a different door: the node row is an ordinary
  /// table write under a policy, and the key is an RPC that checks the caller
  /// because the table it writes has no policy at all.
  Future<({bool success, String? error})> setVoiceRegionCredentials({
    required String nodeId,
    required String apiKey,
    required String secret,
  }) => _change(
    (server, token) => _repository.setVoiceRegionCredentials(
      server.supabaseUrl,
      nodeId,
      apiKey: apiKey,
      secret: secret,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
    failure: 'Failed to change the region\'s credentials',
  );

  Future<({bool success, String? error})> deleteVoiceRegion(String nodeId) =>
      _change(
        (server, token) => _repository.deleteVoiceRegion(
          server.supabaseUrl,
          nodeId,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
        ),
        failure: 'Failed to remove the region',
      );

  Future<({bool success, String? error})> _change(
    Future<APIResponse> Function(Server server, String token) call, {
    required String failure,
  }) async {
    final server = _session.selectedServer;
    if (server == null) return (success: false, error: _session.noTarget(null));

    final response = await _session.callFor(
      server,
      (token) => call(server, token),
    );
    if (!response.success) {
      return (success: false, error: response.error ?? failure);
    }

    _session.regionProbe.invalidate(server.id);
    await _session.refreshDetails(server);
    return (success: true, error: null);
  }
}
