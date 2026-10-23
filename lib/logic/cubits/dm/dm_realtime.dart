part of 'dm_cubit.dart';

/// The server's DMs, live: the doorbells on our own topic that say a DM
/// arrived, changed or was answered, and who is typing to us.
mixin _DmRealtimeMixin
    on
        Cubit<DmState>,
        _DmHistoryMixin,
        _DmConversationsMixin,
        _DmReactionsMixin,
        _DmPinsMixin,
        _DmRequestsMixin,
        _DmCallLogMixin {
  SessionRepository get _session;

  /// The server topic, for `members`: a `users` row moved, which is how a
  /// peer's new chat key is heard without waiting for their next message.
  RealtimeLease? _serverFeed;

  /// A role change rings `members` once per row it touches; one re-read
  /// answers them all.
  Timer? _membersDebounce;

  /// Our own topic, where the database says a DM arrived, changed or was
  /// reacted to, and where peers say they are typing.
  RealtimeLease? _inbox;

  /// The inbox has been joined since this server was set up, so the next
  /// join is a rejoin — after a dropped connection, with doorbells missed.
  bool _inboxJoinedBefore = false;

  /// Who the open conversation is with — the one we tell we are typing.
  String? _typingPeerId;

  /// Expiry timer + rate-limit for the typing indicator.
  Timer? _typingTimer;
  DateTime? _lastTypingSent;

  static const _typingThrottle = Duration(seconds: 2);
  static const _typingTimeout = Duration(seconds: 5);

  // ── Doorbells ───────────────────────────────────────────

  /// The database rings us itself — a DM arrives the same way
  /// whether a person or a bot sent it, and nobody has to remember to say so.
  /// What it carries is ids; the row is what's true, and we go and read it.
  void _setupRealtime(Server server) {
    final user = server.user;
    if (user == null) return;
    _inbox =
        _session.realtime.join(
            server,
            ServerTopics.user(user.id),
            onStatus: _onInboxStatus,
          )
          ?..onBroadcast(ServerEvent.dm, (_) => _onDoorbell())
          ..onBroadcast(ServerEvent.dmChanged, _onChangeDoorbell)
          ..onBroadcast(ServerEvent.dmReaction, _onReactionDoorbell)
          ..onBroadcast(ServerEvent.dmPin, _onPinDoorbell)
          ..onBroadcast(ServerEvent.dmRequests, (_) => _onRequestsDoorbell())
          ..onBroadcast(ServerEvent.blocks, (_) => _onBlocksDoorbell())
          // A call rang, was answered or ended; the open conversation's log may
          // be the one it belongs to.
          ..onBroadcast(ServerEvent.dmCalls, (_) {
            if (state.openPeerId != null) unawaited(refreshCallLog());
          })
          ..onBroadcast(ServerEvent.typing, _onTyping);
    _serverFeed = _session.realtime.join(server, ServerTopics.server(server.id))
      ?..onBroadcast(ServerEvent.members, (_) => _onMembersDoorbell());
  }

  /// Somebody's `users` row moved — a name, an avatar, or a new chat key.
  /// The list carries each peer's key, so reading it again is what notices a
  /// change while the conversation is open, rather than at their next
  /// message or the next launch (`refreshConversations`).
  void _onMembersDoorbell() {
    if (state.conversations.isEmpty) return;
    _membersDebounce?.cancel();
    _membersDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!isClosed) unawaited(refreshConversations());
    });
  }

  /// Reads the lists again once the inbox is back: whatever rang while the
  /// connection was down was never heard. The first join needs nothing —
  /// the lists were just read — unless that read failed, as it does when the
  /// app starts with the server out of reach, and then nothing else would
  /// ever read them again.
  void _onInboxStatus(RealtimeSubscribeStatus status) {
    if (status != RealtimeSubscribeStatus.subscribed || isClosed) return;
    final rejoin = _inboxJoinedBefore;
    _inboxJoinedBefore = true;
    if (rejoin || state.conversationsFailed) unawaited(refreshLists());
  }

  /// The conversation list, the requests waiting and who is blocked — what
  /// the Server DMs list draws. Its "Try again" when they couldn't be read.
  Future<void> refreshLists() =>
      Future.wait([refreshConversations(), refreshRequests(), refreshBlocks()]);

  Future<void> _teardownRealtime() async {
    final inbox = _inbox;
    final feed = _serverFeed;
    _inbox = null;
    _serverFeed = null;
    _membersDebounce?.cancel();
    _inboxJoinedBefore = false;
    _typingPeerId = null;
    _typingTimer?.cancel();
    _typingTimer = null;
    _lastTypingSent = null;
    await inbox?.release();
    await feed?.release();
  }

  @override
  void _joinPeerTopic(String peerId) {
    _leavePeerTopic();
    _typingPeerId = peerId;
    unawaited(refreshOpenLinkState());
  }

  @override
  void _leavePeerTopic() {
    // Leaving the open conversation also clears any pending typing indicator.
    _typingTimer?.cancel();
    _typingTimer = null;
    _lastTypingSent = null;
    _typingPeerId = null;
  }

  void _onChangeDoorbell(Map<String, dynamic> payload) {
    if (isClosed || state.chatStatus != DmChatStatus.ready) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (messageId != null) unawaited(refreshMessage(messageId));
    // The conversation list shows a preview of the newest message, which an
    // edit or delete can change.
    unawaited(refreshConversations());
  }

  /// A ring without a message id is an older client; fall back to refreshing
  /// everything loaded.
  void _onReactionDoorbell(Map<String, dynamic> payload) {
    if (isClosed) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (messageId != null) {
      unawaited(refreshReactionsFor(messageId));
    } else {
      unawaited(refreshReactions());
    }
  }

  void _onDoorbell() {
    if (isClosed) return;
    unawaited(refreshConversations());
    if (state.chatStatus == DmChatStatus.ready) {
      unawaited(_fetchAfterLatest());
      // A reply to our request is its acceptance.
      if (state.openLinkState != DmLinkState.open) {
        unawaited(refreshOpenLinkState());
      }
    }
  }

  /// A request arrived, ours was accepted, or another of our devices answered
  /// one.
  void _onRequestsDoorbell() {
    if (isClosed) return;
    unawaited(refreshRequests());
    unawaited(refreshConversations());
    if (state.openPeerId != null) unawaited(refreshOpenLinkState());
  }

  void _onBlocksDoorbell() {
    if (isClosed) return;
    unawaited(refreshBlocks());
    unawaited(refreshRequests());
  }

  // ── Typing ──────────────────────────────────────────────

  /// Tell the open peer we're typing (throttled). Sent to their topic without
  /// joining it — nobody but them may — so it goes over HTTP.
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingThrottle) {
      return;
    }
    final server = _server;
    final user = server?.user;
    final peerId = _typingPeerId;
    if (server == null || user == null || peerId == null) return;
    _lastTypingSent = now;
    unawaited(
      _session.realtime.ring(
        server,
        ServerTopics.user(peerId),
        ServerEvent.typing,
        {'from': user.id, 'name': user.displayName},
      ),
    );
  }

  void _onTyping(Map<String, dynamic> payload) {
    if (isClosed) return;
    final from = BroadcastPayload.stringOf(payload, 'from');
    // Only surface typing for the conversation the user currently has open.
    if (from == null || from != state.openPeerId) return;
    // The name this device already has for them, not the one in the event:
    // any member may send on this topic, so a name read from it is whatever
    // the sender chose to put there.
    final name = state.openPeerName;
    if (name == null) return;

    _typingTimer?.cancel();
    _typingTimer = Timer(_typingTimeout, () {
      if (!isClosed) emit(state.copyWith(clearTyping: true));
    });
    if (state.typingPeerName != name) {
      emit(state.copyWith(typingPeerName: name));
    }
  }

  @override
  void _onOpenPeerMessage() {
    _typingTimer?.cancel();
    _typingTimer = null;
    if (!isClosed && state.typingPeerName != null) {
      emit(state.copyWith(clearTyping: true));
    }
  }
}
