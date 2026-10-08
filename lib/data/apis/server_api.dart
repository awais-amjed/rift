import '../classes/server_limits.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// A server itself: creating one, its listing token, and its settings.
///
/// A settings write ends with a re-read of the server's details
/// ([SessionRepository.refreshDetails]), so the list shows what the server
/// stored before the call answers. Telling the other members is the
/// caller's: it rings `ServerEventsCubit.notifyServerChanged`, because the
/// doorbell is a cubit's and this class holds nothing.
///
/// Holds nothing, so a widget builds one from the session.
class ServerApi {
  final SessionRepository _session;

  ServerApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// Creates a new server. On success returns the single-use admin invite code.
  ///
  /// The one call here made on the operator's service key rather than a
  /// session: there is no server to be signed in to yet.
  Future<({bool success, String? inviteCode, String? error})> createServer({
    required String supabaseUrl,
    required String serviceKey,
    required String name,
    String? iconUrl,
    required String livekitUrl,
    required String livekitApiKey,
    required String livekitSecretKey,
  }) async {
    final response = await _repository.createServer(
      supabaseUrl,
      serviceKey: serviceKey,
      name: name,
      iconUrl: iconUrl,
      livekitUrl: livekitUrl,
      livekitApiKey: livekitApiKey,
      livekitSecretKey: livekitSecretKey,
    );

    if (!response.success) {
      return (success: false, inviteCode: null, error: response.error);
    }

    final data = response.data as Map<String, dynamic>;
    final inviteCode = data['invite_code'] as String;
    return (success: true, inviteCode: inviteCode, error: null);
  }

  /// A one-time token proving an admin of [serverId] wants it listed.
  ///
  /// Handed to central, which redeems it against this server's own domain
  /// before writing a directory entry — see `publish_server` there.
  ///
  /// Returns the server's own reason on failure rather than a bare null. It
  /// used to return null for everything, and every caller said the same thing
  /// — "only a server admin can list this server publicly" — so an endpoint
  /// that was failing to boot, a server that was unreachable and a genuine
  /// refusal all arrived as an accusation that the admin was not an admin.
  Future<({String? token, String? error})> listingToken({
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (token: null, error: 'That server is not open here any more.');
    }

    final response = await _session.callFor(
      server,
      (token) =>
          _repository.listingToken(server.supabaseUrl, bearerToken: token),
    );
    if (!response.success) {
      return (token: null, error: response.error?.toString());
    }

    final token = (response.data as Map<String, dynamic>?)?['token'] as String?;
    return token == null
        ? (token: null, error: 'This server did not return a listing token.')
        : (token: token, error: null);
  }

  /// Update the settings of [serverId], or of the selected server (admin only).
  /// Only non-null fields are sent; the LiveKit API key / secret are write-only
  /// (never stored client side — the client only keeps the URL).
  ///
  /// Ends with a re-read rather than applying the reply by hand: the server
  /// may clamp or refuse a limit, and the re-read shows what it stored.
  Future<({bool success, String? error})> updateServerDetails({
    String? name,
    String? iconUrl,
    String? livekitUrl,
    String? livekitApiKey,
    String? livekitSecretKey,
    ServerLimits? limits,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (success: false, error: _session.noTarget(serverId));
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.updateServer(
        server.supabaseUrl,
        bearerToken: token,
        name: name,
        iconUrl: iconUrl,
        livekitUrl: livekitUrl,
        livekitApiKey: livekitApiKey,
        livekitSecretKey: livekitSecretKey,
        limits: limits,
      ),
    );

    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to update server',
      );
    }

    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  /// The default voice region's address and key, which are the *server's*
  /// LiveKit URL and key pair.
  ///
  /// Written through `update_server` rather than through the node, because
  /// `servers.livekit_url` and `server_secrets` are where they live, and a
  /// trigger carries the address into the default node. Writing the node
  /// instead would leave the two disagreeing, and the column is what an older
  /// client still reads. Each is sent only if given, and `update_server`
  /// leaves alone what it isn't sent. The other regions are `VoiceRegionsApi`.
  ///
  /// Ends like those calls — the probe's measurement thrown away, the server
  /// re-read — because the default node's row may just have changed
  /// underneath us and the copy held here would still name the old box.
  Future<({bool success, String? error})> updateDefaultVoiceRegion({
    String? url,
    String? apiKey,
    String? secret,
  }) async {
    final server = _session.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }
    if (url == null && apiKey == null && secret == null) {
      return (success: true, error: null);
    }

    final result = await updateServerDetails(
      livekitUrl: url,
      livekitApiKey: apiKey,
      livekitSecretKey: secret,
      serverId: server.id,
    );
    if (result.success) _session.regionProbe.invalidate(server.id);
    return result;
  }
}
