part of 'central_dm_repository.dart';

/// The central friends graph: who you are friends with, who is waiting on an
/// answer, and who you have shut out.
///
/// Every one of these is an RPC rather than a table write, and that is the
/// design rather than a convenience (central migration 012). There is no
/// INSERT, UPDATE or DELETE grant on `friendships` or `blocks` at all, because
/// each change carries a rule with it — a request may not be accepted by the
/// person who sent it, a block has to tear the friendship down with it — and a
/// rule spelled in a policy has to be re-derived by every policy that reads the
/// table afterwards.
mixin _CentralDmFriendsMixin {
  SupabaseClient get _client;

  /// Errors these RPCs raise by name, so a caller can tell "they blocked you"
  /// from "the network is down" without matching on prose.
  static const _codes = [
    'blocked',
    'cannot_friend_self',
    'cannot_block_self',
    'no_pending_request',
    'no_such_user',
    'not_your_request',
    'recipient_has_no_profile',
    'sender_has_no_profile',
  ];

  /// The whole graph in one call — see [FriendDirectory] for why it is one.
  Future<APIResponse> listFriends() async {
    try {
      final result = await _client.rpc('friend_list');
      return APIResponse.success(
        FriendDirectory.fromJson((result as Map).cast<String, dynamic>()),
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Ask somebody to be friends. Idempotent, and it collapses the crossing
  /// case: asking somebody who has already asked you accepts instead. Answers
  /// the resulting state.
  ///
  /// By id, so its callers are the places one is already to hand — a
  /// conversation you used to have, somebody you unfriended. A handle goes
  /// through [requestFriendByHandle] instead.
  Future<APIResponse> requestFriend(String userId) =>
      _call('friend_request', {'p_user': userId});

  /// The only way a handle becomes a person on central.
  ///
  /// It resolves and asks in one statement, and that is the design rather than
  /// a shortcut. A `find_user(handle)` that merely answered with an id would be
  /// a cheap, silent, repeatable oracle over the whole membership — the
  /// enumeration migration 012 removed, minus the typing. Here the answer *is*
  /// the request: every successful lookup lands in somebody's Pending list,
  /// under the caller's handle, where it can be declined or blocked.
  ///
  /// Answers `(handle:, state:)` — the handle as the server spells it, and
  /// where the pair now stands, which is `outgoing` normally and `friends` when
  /// the request crossed one of theirs.
  ///
  /// The two refusals are different on purpose. `no_such_user` covers a handle
  /// nobody owns, a handle that could never be valid, **and** one whose owner
  /// has blocked the caller — the third has to be indistinguishable from the
  /// first. `blocked` means the caller blocked *them*, which is their own
  /// decision and one they can undo, so it is said plainly.
  Future<APIResponse> requestFriendByHandle(String handle) async {
    try {
      final result = await _client.rpc(
        'friend_request_by_handle',
        params: {'p_handle': handle},
      );
      final row = (result as Map).cast<String, dynamic>();
      return APIResponse.success((
        handle: row['handle'] as String? ?? handle,
        state: FriendshipState.parse(row['state']),
      ));
    } on PostgrestException catch (e) {
      return _rpcFailure(e, _codes);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Accept or decline something *they* asked for.
  ///
  /// Declining removes the request and nothing else. A request arrives empty,
  /// so there is nothing of theirs to throw away, and any conversation the two
  /// already had is older than the request and not its to erase.
  Future<APIResponse> respondToRequest({
    required String userId,
    required bool accept,
  }) => _call('respond_friend_request', {
    'p_user': userId,
    'p_accept': accept,
  });

  /// Ends the relationship in either state — unfriending a friend, or
  /// withdrawing a request. The conversation survives: it is not something one
  /// of two people gets to erase from the other.
  Future<APIResponse> unfriend(String userId) =>
      _call('unfriend', {'p_user': userId});

  Future<APIResponse> blockUser(String userId) =>
      _call('block_user', {'p_user': userId});

  Future<APIResponse> unblockUser(String userId) =>
      _call('unblock_user', {'p_user': userId});

  /// Every one of these answers a state string; this is the one place that
  /// turns it into a [FriendshipState].
  Future<APIResponse> _call(String rpc, Map<String, dynamic> params) async {
    try {
      final result = await _client.rpc(rpc, params: params);
      return APIResponse.success(FriendshipState.parse(result));
    } on PostgrestException catch (e) {
      return _rpcFailure(e, _codes);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
