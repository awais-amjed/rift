part of 'central_dm_cubit.dart';

/// The central friends graph — asking, answering, ending, blocking.
///
/// Every change here goes to the server and comes back through
/// [loadFriends] rather than being patched into state optimistically. That is
/// deliberate and it is the house rule (`rift-no-optimistic-ui`): a friendship
/// has two sides and the server is the only thing that knows both, so a
/// locally-applied "accepted" that the server then refuses would leave a
/// conversation open that the next send bounces out of.
///
/// Refusals are named, not guessed at: `no_such_user`, `blocked`,
/// `not_your_request`, `no_pending_request` come back as error codes from the
/// RPCs, and the wording here is the only place they become sentences.
mixin _CentralDmFriendsMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;

  /// Implemented by the conversations mixin.
  Future<void> refreshConversations();

  /// Implemented by the history mixin.
  void closeConversation();

  /// Load the whole graph. Cheap enough to be the answer to every change:
  /// one RPC, four short lists.
  Future<void> loadFriends() async {
    final response = await _repo.listFriends();
    if (isClosed || !response.success) return;
    emit(state.copyWith(graph: response.data as FriendDirectory));
  }

  /// Ask somebody to be friends. Asking somebody who has already asked you
  /// accepts instead — the server collapses that case, so there is no "you
  /// both have a pending request" to explain.
  ///
  /// By id: for a person already on screen. A handle typed into the add field
  /// goes through [addFriendByHandle].
  Future<bool> addFriend(String peerId) =>
      _change(() => _repo.requestFriend(peerId));

  /// Ask by handle, typed in full — the only way to reach somebody who is not
  /// already somewhere on this screen.
  ///
  /// The sentence is built here rather than by the field, because which one is
  /// true depends on the state the server answers with and the field never
  /// sees it: asking somebody who had already asked you makes you friends on
  /// the spot, and telling them "request sent" would be a lie about something
  /// they can see for themselves one tab over.
  Future<bool> addFriendByHandle(String handle) async {
    final typed = handle.trim().replaceFirst(RegExp(r'^@'), '');
    if (typed.isEmpty) return false;

    final response = await _repo.requestFriendByHandle(typed);
    if (isClosed) return false;
    if (!response.success) {
      HelperMethods.showError(error: _reasonFor(response, handle: typed));
      return false;
    }

    final result = response.data as ({String handle, FriendshipState state});
    await loadFriends();
    HelperMethods.showSuccess(
      message: result.state == FriendshipState.friends
          ? 'You and @${result.handle} are now friends.'
          : 'Friend request sent to @${result.handle}.',
    );
    return true;
  }

  Future<bool> acceptRequest(String peerId) =>
      _change(() => _repo.respondToRequest(userId: peerId, accept: true));

  /// Declining removes the request and nothing else — a request carries no
  /// message, and an older conversation with the same person is not the
  /// request's to erase.
  Future<bool> declineRequest(String peerId) =>
      _change(() => _repo.respondToRequest(userId: peerId, accept: false));

  /// Ends the relationship, not the history. The conversation stays where it
  /// is and stays readable; what changes is that the next message from either
  /// side is a request again.
  Future<bool> removeFriend(String peerId) =>
      _change(() => _repo.unfriend(peerId));

  Future<bool> blockPeer(String peerId) =>
      _change(() => _repo.blockUser(peerId), closeIfOpen: peerId);

  Future<bool> unblockPeer(String peerId) =>
      _change(() => _repo.unblockUser(peerId));

  /// One shape for all six: run it, say why if it failed, then re-read the
  /// graph *and* the conversations — most of these move a row between the two
  /// sidebar sections, and a couple delete messages outright.
  Future<bool> _change(
    Future<APIResponse> Function() call, {
    String? closeIfOpen,
  }) async {
    final response = await call();
    if (isClosed) return false;
    if (!response.success) {
      HelperMethods.showError(error: _reasonFor(response));
      return false;
    }
    if (closeIfOpen != null && state.openPeerId == closeIfOpen) {
      closeConversation();
    }
    await loadFriends();
    unawaited(refreshConversations());
    return true;
  }

  /// [handle] is what the user typed, for the one message that can name it.
  String _reasonFor(APIResponse response, {String? handle}) {
    final named = handle == null ? 'that handle' : '@$handle';
    return switch (response.errorCode) {
      // The server says this for a handle nobody owns, a handle that could
      // never be valid, and a handle whose owner has blocked you. One sentence
      // for all three, because the third has to be indistinguishable from the
      // first — anything else is a way to check whether you have been blocked.
      'no_such_user' => 'Nobody is using $named.',
      // This one is the caller's own decision, so it names it and says what to
      // do about it.
      'blocked' => 'You have $named blocked. Unblock them to send a request.',
      'cannot_friend_self' => 'That is you.',
      'no_pending_request' => 'That request is no longer waiting.',
      'not_your_request' => 'That request is yours to withdraw, not to accept.',
      'recipient_has_no_profile' => 'That account no longer exists.',
      'sender_has_no_profile' => 'Claim a handle before adding anyone.',
      _ => response.error ?? 'Could not do that just now.',
    };
  }
}
