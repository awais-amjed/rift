part of 'server_cubit.dart';

/// Calls between two members, on a **named** server.
///
/// Named rather than selected, every one of them: a call rings on whichever
/// server it was placed on, and the person answering may be looking at
/// another. Reading the selection here is how an answer would end up sent to
/// the wrong database.
mixin _ServerDmCallsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  VoiceRegionProbe get _regionProbe;

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  String _keyOf(Server server) => server.supabaseKey ?? '';

  Future<APIResponse> startDmCall(Server server, String peerId) => _callFor(
    server,
    (token) => _repository.startDmCall(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      peerId: peerId,
    ),
  );

  Future<APIResponse> answerDmCall(Server server, String callId) => _callFor(
    server,
    (token) => _repository.answerDmCall(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      callId: callId,
    ),
  );

  Future<APIResponse> endDmCall(Server server, String callId) => _callFor(
    server,
    (token) => _repository.endDmCall(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      callId: callId,
    ),
  );

  Future<APIResponse> dmCallAlive(Server server, String callId) => _callFor(
    server,
    (token) => _repository.dmCallAlive(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      callId: callId,
    ),
  );

  Future<APIResponse> myDmCalls(
    Server server, {
    List<String> known = const [],
  }) => _callFor(
    server,
    (token) => _repository.myDmCalls(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      known: known,
    ),
  );

  Future<APIResponse> dmCallLog(
    Server server, {
    required String peerId,
    DateTime? since,
  }) => _callFor(
    server,
    (token) => _repository.dmCallLog(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      peerId: peerId,
      since: since,
    ),
  );

  /// A LiveKit token for [callId]'s room, measured the same way a channel's
  /// is: the nearest region is suggested, and forgotten again if the join is
  /// refused, so a region that died is not suggested twice.
  Future<APIResponse> getDmCallToken(
    Server server,
    String callId, {
    bool screenShare = false,
    bool soundShare = false,
  }) async {
    final preferred = await _regionProbe.nearest(
      server.id,
      server.livekitNodes,
      load: state.regionLoad,
    );
    final response = await _callFor(
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
    if (!response.success) _regionProbe.invalidate(server.id);
    return response;
  }
}
