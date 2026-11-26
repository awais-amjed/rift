part of 'server_repository.dart';

/// Who may start a DM with whom, and the requests that result.
///
/// A member's setting is a column on their own row. The pair ledger behind it
/// is never read directly — `dm_link_state` answers for one peer and hides
/// from a sender that their request was ignored, which a policy could not.
mixin _DmRequestsApiMixin {
  ServerDb get _db;

  /// Servers, by URL, with no `dm_lists`: asked the three calls instead.
  final Set<String> _noDmLists = {};

  /// The DM list, the requests waiting and who is blocked, in one call
  /// (`dm_lists`, self-host 064): `{conversations, requests, blocks}`, each as
  /// [listDmConversations], [dmRequests] and [listBlocks] answer it. A server
  /// older than that answers `PGRST202`, once; after that the answer is
  /// given here without asking.
  Future<APIResponse> dmLists(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async {
    if (_noDmLists.contains(supabaseUrl)) {
      return APIResponse(
        success: false,
        error: 'This server has no dm_lists',
        errorCode: 'PGRST202',
      );
    }
    final response = await ServerDb.run(
      () => _db.client(supabaseUrl, anonKey, bearerToken).rpc('dm_lists'),
    );
    if (response.errorCode == 'PGRST202') _noDmLists.add(supabaseUrl);
    return response;
  }

  /// Set who may start a DM with the caller: `everyone`, `requests` or
  /// `nobody`.
  Future<APIResponse> setDmPolicy(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String policy,
  }) {
    return ServerDb.run(() async {
      await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('users')
          .update({'dm_policy': policy})
          .eq('id', userId);
      return null;
    });
  }

  /// `none`, `open`, `waiting`, `asked` or `ignored`.
  Future<APIResponse> dmLinkState(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String peerId,
  }) {
    return ServerDb.run(
      () => _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc('dm_link_state', params: {'p_peer': peerId}),
    );
  }

  /// The caller's waiting requests, in the `dm_conversations` row shape.
  Future<APIResponse> dmRequests(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(
      () => _db.client(supabaseUrl, anonKey, bearerToken).rpc('dm_requests'),
    );
  }

  /// Accept or ignore the request from [peerId].
  Future<APIResponse> answerDmRequest(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String peerId,
    required bool accept,
  }) {
    return ServerDb.run(
      () => _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'answer_dm_request',
            params: {'p_peer': peerId, 'p_accept': accept},
          ),
    );
  }
}
