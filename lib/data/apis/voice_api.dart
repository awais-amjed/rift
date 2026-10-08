import '../classes/api_response.dart';
import '../classes/region_load.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/voice_region_probe.dart';

/// The server's side of a call: the LiveKit token to join one, who is in
/// which channel, and moving or removing somebody.
///
/// Holds nothing, so a widget builds one from the session. The measurement
/// of which region is nearest is the session's ([SessionRepository.regionProbe]),
/// so it outlives every one of these.
class VoiceApi {
  final SessionRepository _session;

  VoiceApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;
  VoiceRegionProbe get _probe => _session.regionProbe;

  /// Returns a LiveKit JWT for [channelId] on the selected server.
  ///
  /// Measures which of the server's LiveKit nodes is nearest first, and sends
  /// that along — see [VoiceRegionProbe]. It costs nothing on the usual
  /// server, which has one node and therefore nothing to measure, and the
  /// answer is cached for half an hour on the servers that have several.
  /// A probe that fails is not an error: the server falls back to its default
  /// node, which is what every client did before there was anything to
  /// choose.
  Future<APIResponse> getChannelToken(
    String channelId, {
    bool screenShare = false,
    bool soundShare = false,
  }) async {
    final server = _session.selectedServer;
    if (server == null) return APIResponse.error(_session.noTarget(null));

    final preferred = await _probe.nearest(server.id, server.livekitNodes);
    final response = await _session.callFor(
      server,
      (token) => _repository.getChannelToken(
        server.supabaseUrl,
        channelId,
        screenShare: screenShare,
        soundShare: soundShare,
        preferredNodeId: preferred,
        bearerToken: token,
      ),
    );

    // A refusal throws away the measurement, and that is the whole reason
    // this is not a plain `return`.
    //
    // The cache holds for half an hour, which is fine while every region is
    // up and wrong the moment one is not: a region that died after being
    // measured goes on being offered as the nearest, the server takes the
    // suggestion, and the join fails again — for as long as the cache lasts.
    // Found by killing a region under a live call: both clients dropped, and
    // Try again kept failing on the dead region while a fresh request naming
    // no preference reached the live one immediately.
    //
    // Re-measuring costs one request per region and a node that is down
    // cannot answer it, so the next attempt cannot suggest it.
    if (!response.success) _probe.invalidate(server.id);
    return response;
  }

  /// A LiveKit token for [callId]'s room on [server], measured the same way a
  /// channel's is: the nearest region is suggested, and forgotten again if
  /// the join is refused, so a region that died is not suggested twice.
  ///
  /// Named rather than selected: a call rings on whichever server it was
  /// placed on, and the person answering may be looking at another.
  Future<APIResponse> getDmCallToken(
    Server server,
    String callId, {
    bool screenShare = false,
    bool soundShare = false,
  }) async {
    final preferred = await _probe.nearest(server.id, server.livekitNodes);
    final response = await _session.callFor(
      server,
      (token) => _repository.getDmCallToken(
        server.supabaseUrl,
        callId,
        screenShare: screenShare,
        soundShare: soundShare,
        preferredNodeId: preferred,
        bearerToken: token,
      ),
    );
    if (!response.success) _probe.invalidate(server.id);
    return response;
  }

  /// Moves the call in [channelId] to [nodeId] (channel manager or admin).
  ///
  /// Everybody in it reconnects, which is a second or two of silence for the
  /// whole room — so this is a deliberate action, never a side effect of
  /// changing a setting on a channel nobody is in.
  Future<APIResponse> moveCall({
    required String channelId,
    required String nodeId,
  }) => _onSelected(
    (server, token) => _repository.moveCall(
      server.supabaseUrl,
      channelId: channelId,
      nodeId: nodeId,
      bearerToken: token,
    ),
  );

  /// Moves a member into another voice channel (requires channel manager or
  /// server admin). They have to be in a call for there to be anything to move.
  Future<APIResponse> moveUser({
    required String userId,
    required String channelId,
  }) => _onSelected(
    (server, token) => _repository.moveUser(
      server.supabaseUrl,
      bearerToken: token,
      userId: userId,
      channelId: channelId,
    ),
  );

  /// Disconnects a member from the voice channel they're in (requires channel
  /// manager or server admin). They have to be in a call for there to be
  /// anything to end, and nothing stops them rejoining — see `kick_user`.
  Future<APIResponse> kickUser({required String userId}) => _onSelected(
    (server, token) => _repository.kickUser(
      server.supabaseUrl,
      bearerToken: token,
      userId: userId,
    ),
  );

  /// [call] against the selected server, with its token.
  Future<APIResponse> _onSelected(
    Future<APIResponse> Function(Server server, String token) call,
  ) {
    final server = _session.selectedServer;
    if (server == null) {
      return Future.value(APIResponse.error(_session.noTarget(null)));
    }
    return _session.callFor(server, (token) => call(server, token));
  }

  /// Who is in which voice channel on the selected server, straight from
  /// LiveKit: `{roster: {userId: channelId}}` — and how busy each region is
  /// while we are asking, which lands in [SessionRepository.regionProbe]
  /// under the server that was asked.
  ///
  /// The load rides along because this call already fans out across every
  /// region — it is the one request that has to touch them all — so learning
  /// it costs nothing, and it is polled often enough to be current when a
  /// manager opens the picker.
  Future<APIResponse> voiceRoster() async {
    final server = _session.selectedServer;
    if (server == null) return APIResponse.error(_session.noTarget(null));

    final response = await _session.callFor(
      server,
      (token) =>
          _repository.voiceRoster(server.supabaseUrl, bearerToken: token),
    );
    if (!response.success) return response;

    final data = response.data;
    if (data is! Map) return response;
    final regions = data['regions'];
    if (regions is! List) return response;

    _probe.noteLoad(server.id, {
      for (final row in regions)
        if (row is Map<String, dynamic>)
          if (RegionLoad.fromJson(row) case final load
              when load.nodeId.isNotEmpty)
            load.nodeId: load,
    });
    return response;
  }
}
