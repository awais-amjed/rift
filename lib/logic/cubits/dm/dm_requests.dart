part of 'dm_cubit.dart';

/// Message requests, blocks, and where we stand with the open conversation.
///
/// A request is a first message from somebody new to a member set to "ask me
/// first". The server keeps it out of [DmState.conversations] and out of the
/// unread badges; this holds it in [DmState.requests] until it is accepted,
/// ignored, or its sender is blocked.
mixin _DmRequestsMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  ModerationApi get _moderation;

  Future<List<DmConversation>?> _conversationsFrom(
    List<Map<String, dynamic>> rows,
  );
  Future<void> refreshConversations();

  /// The requests waiting on us, previews decrypted like the conversation
  /// list's — the recipient of a request can read it, which is the point.
  Future<void> refreshRequests() async {
    final response = await _moderation.dmRequests();
    if (isClosed || !response.success) return;
    final rows = (response.data as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final requests = await _conversationsFrom(rows);
    if (isClosed || requests == null) return;
    emit(state.copyWith(requests: requests));
  }

  Future<void> refreshBlocks() async {
    final response = await _moderation.listBlocks();
    if (isClosed || !response.success) return;
    emit(
      state.copyWith(
        blockedIds: (response.data as List).cast<String>().toSet(),
      ),
    );
  }

  /// Ask the server where we stand with the open conversation's peer. Called
  /// on opening one, after sending into it, and when a request changes.
  Future<void> refreshOpenLinkState() async {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    final response = await _moderation.dmLinkState(peerId: peerId);
    if (isClosed || state.openPeerId != peerId) return;
    // An older server has no such function; open is what it always meant.
    final linkState = response.success
        ? DmLinkState.fromString(response.data as String?)
        : DmLinkState.open;

    // With nothing between us yet, their setting is what the composer has to
    // say before a word is typed. Otherwise it has no say.
    DmPolicy? policy;
    if (linkState == DmLinkState.none) {
      policy = (await _serverCubit.findMember(peerId))?.dmPolicy;
      if (isClosed || state.openPeerId != peerId) return;
    }
    if (linkState != state.openLinkState || policy != state.openPeerPolicy) {
      emit(
        state.copyWith(
          openLinkState: linkState,
          openPeerPolicy: policy,
          clearOpenPeerPolicy: policy == null,
        ),
      );
    }
  }

  /// Accept or ignore the request from [peerId]. Accepting moves it into the
  /// conversation list and rings the sender, whose composer opens; ignoring
  /// tells nobody.
  Future<APIResponse> answerRequest(
    String peerId, {
    required bool accept,
  }) async {
    final response = await _moderation.answerDmRequest(
      peerId: peerId,
      accept: accept,
    );
    if (isClosed) return response;
    if (response.success) {
      emit(
        state.copyWith(
          requests: [
            for (final r in state.requests)
              if (r.peerId != peerId) r,
          ],
        ),
      );
      if (accept) unawaited(refreshConversations());
      if (state.openPeerId == peerId) unawaited(refreshOpenLinkState());
    }
    return response;
  }

  /// Block or unblock [peerId]. A block also takes their request, if any,
  /// out of the list — the server stops listing it, and so does this.
  Future<APIResponse> setBlocked(String peerId, {required bool blocked}) async {
    final response = await _moderation.setBlocked(
      peerId: peerId,
      blocked: blocked,
    );
    if (isClosed || !response.success) return response;
    final ids = {...state.blockedIds};
    blocked ? ids.add(peerId) : ids.remove(peerId);
    emit(
      state.copyWith(
        blockedIds: ids,
        requests: blocked
            ? [
                for (final r in state.requests)
                  if (r.peerId != peerId) r,
              ]
            : null,
      ),
    );
    if (!blocked) unawaited(refreshRequests());
    return response;
  }
}
