part of 'server_repository.dart';

/// Calls between two members: ringing, answering, hanging up, and the log.
///
/// Every write is an RPC, because the rules are the server's — who may call
/// whom, and what a hang-up is called depends on who pressed it and when. The
/// table itself has no grant. The one edge function is the token, which needs
/// the LiveKit secret.
mixin _DmCallsApiMixin {
  ServerDb get _db;

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  Future<APIResponse> _rpc(
    String supabaseUrl,
    String anonKey,
    String? bearerToken,
    String name, [
    Map<String, dynamic>? params,
  ]) => ServerDb.run(
    () => _db
        .client(supabaseUrl, anonKey, bearerToken)
        .rpc(name, params: params),
  );

  /// Ring [peerId]. Answers the call — which is theirs ringing us, answered,
  /// if they were already calling.
  Future<APIResponse> startDmCall(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String peerId,
  }) => _rpc(supabaseUrl, anonKey, bearerToken, 'start_dm_call', {
    'p_peer': peerId,
  });

  Future<APIResponse> answerDmCall(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String callId,
  }) => _rpc(supabaseUrl, anonKey, bearerToken, 'answer_dm_call', {
    'p_call': callId,
  });

  Future<APIResponse> endDmCall(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String callId,
  }) => _rpc(supabaseUrl, anonKey, bearerToken, 'end_dm_call', {
    'p_call': callId,
  });

  /// The heartbeat. `true` while the call is still going.
  Future<APIResponse> dmCallAlive(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String callId,
  }) => _rpc(supabaseUrl, anonKey, bearerToken, 'dm_call_alive', {
    'p_call': callId,
  });

  /// Calls still going, plus [known] however they stand.
  Future<APIResponse> myDmCalls(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    List<String> known = const [],
  }) => _rpc(supabaseUrl, anonKey, bearerToken, 'my_dm_calls', {
    'p_known': known,
  });

  /// One conversation's ended calls since [since], newest first.
  Future<APIResponse> dmCallLog(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String peerId,
    DateTime? since,
  }) => _rpc(supabaseUrl, anonKey, bearerToken, 'dm_call_log', {
    'p_peer': peerId,
    'p_since': since?.toUtc().toIso8601String(),
  });

  /// A LiveKit token for [callId]'s room — the same answer as a channel's.
  Future<APIResponse> getDmCallToken(
    String supabaseUrl,
    String callId, {
    bool screenShare = false,
    bool soundShare = false,
    String? preferredNodeId,
    String? bearerToken,
  }) => _post(supabaseUrl, 'get_dm_call_token', {
    'call_id': callId,
    'screen_share': screenShare,
    'sound_share': soundShare,
    'device_id': DeviceId.current,
    'preferred_node_id': preferredNodeId,
  }, bearerToken: bearerToken);
}
