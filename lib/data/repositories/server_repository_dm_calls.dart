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
    () =>
        _db.client(supabaseUrl, anonKey, bearerToken).rpc(name, params: params),
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

  /// End [callId] only if it is still ringing: a decline, or the caller
  /// giving up at thirty seconds. Answers the row as the server now has it —
  /// ended, or, when it had been answered after all, still going.
  ///
  /// `end_dm_call` ends a call in any state. Pressed on a ring that was
  /// answered a moment ago — Decline on the phone after answering on the PC,
  /// or the caller's thirty seconds running out while the answer was on its
  /// way — it hung up a call somebody was in (review, Nov 22). The server's
  /// `end_dm_ring` ends it only while unanswered, under the lock an answer
  /// takes. A server without it (before console 1.9.0) is asked first
  /// instead, which leaves the gap of one round trip.
  Future<APIResponse> endDmRing(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String callId,
  }) async {
    final ended = await endDmRingOnServer(
      supabaseUrl,
      anonKey: anonKey,
      bearerToken: bearerToken,
      callId: callId,
    );
    if (ended.errorCode != 'PGRST202') return ended;
    final asked = await myDmCalls(
      supabaseUrl,
      anonKey: anonKey,
      bearerToken: bearerToken,
      known: [callId],
    );
    final rows = asked.success ? asked.data : null;
    if (rows is List) {
      for (final row in rows) {
        if (row is Map<String, dynamic> &&
            row['id'] == callId &&
            row['answered_at'] != null) {
          return APIResponse.success(row);
        }
      }
    }
    return endDmCall(
      supabaseUrl,
      anonKey: anonKey,
      bearerToken: bearerToken,
      callId: callId,
    );
  }

  /// The server's `end_dm_ring` alone; [endDmRing] is what to call. A
  /// server without it answers `PGRST202`.
  Future<APIResponse> endDmRingOnServer(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String callId,
  }) => _rpc(supabaseUrl, anonKey, bearerToken, 'end_dm_ring', {
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
    bool watch = false,
    String? preferredNodeId,
    String? bearerToken,
  }) => _post(supabaseUrl, 'get_dm_call_token', {
    'call_id': callId,
    'screen_share': screenShare,
    'sound_share': soundShare,
    'watch': watch,
    'device_id': DeviceId.current,
    'preferred_node_id': preferredNodeId,
  }, bearerToken: bearerToken);
}
