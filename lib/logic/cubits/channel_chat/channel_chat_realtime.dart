part of 'channel_chat_cubit.dart';

/// The open channel, live: who is typing, and the doorbells that say something
/// changed.
///
/// The doorbells come from the database (migration 017), on the server's topic
/// for an open channel and on our own for a private one, so a message arrives
/// whoever wrote it and however — a bot writing through the REST API included,
/// which no client-rung doorbell ever covered. They carry ids, never text: the
/// row is what's true, and the receiver always goes and reads it. The channel's
/// own topic carries only typing.
mixin _ChannelChatRealtimeMixin
    on
        Cubit<ChannelChatState>,
        _ChannelChatHistoryMixin,
        _ChannelChatReactionsMixin {
  /// Re-open the channel — how a member waiting for a key retries once someone
  /// who can heal them comes online.
  Future<void> retry();

  /// The open channel's own topic, for typing.
  RealtimeLease? _rtTopic;

  /// Where the database says what happened here: the server's topic and our
  /// own. Shared joins — the unread badges hold the same two.
  final List<RealtimeLease> _rtFeeds = [];

  /// Per-user expiry timers for typing indicators (removed when they lapse).
  final Map<String, Timer> _typingTimers = {};

  /// Rate-limit for our outgoing typing pings.
  DateTime? _lastTypingSent;

  static const _typingThrottle = Duration(seconds: 2);
  static const _typingTimeout = Duration(seconds: 5);

  // ──────────────────────────────────────────────────────────
  // Realtime doorbell
  // ──────────────────────────────────────────────────────────

  void _setupRealtime(Server server, String channelId) {
    final realtime = _serverCubit.realtime;
    _rtTopic = realtime.join(server, ServerTopics.chat(channelId))
      ?..onBroadcast(ServerEvent.typing, _onTyping);

    final me = server.user?.id;
    bool here(RealtimePayload message) =>
        BroadcastPayload.stringOf(message, 'channel_id') == channelId;
    for (final topic in [
      ServerTopics.server(server.id),
      if (me != null) ServerTopics.user(me),
    ]) {
      final feed = realtime.join(server, topic);
      if (feed == null) continue;
      feed
        ..onBroadcast(ServerEvent.message, (message) {
          // Our own sends are already on screen from their insert.
          if (!here(message)) return;
          if (BroadcastPayload.stringOf(message, 'sender_id') == me) return;
          _onDoorbell();
        })
        ..onBroadcast(ServerEvent.messageChanged, (message) {
          if (here(message)) _onChangeDoorbell(message);
        })
        ..onBroadcast(ServerEvent.reaction, (message) {
          if (here(message)) _onReactionDoorbell(message);
        });
      _rtFeeds.add(feed);
    }
  }

  Future<void> _teardownRealtime() async {
    final topic = _rtTopic;
    final feeds = [..._rtFeeds];
    _rtTopic = null;
    _rtFeeds.clear();
    _lastTypingSent = null;
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    await topic?.release();
    for (final feed in feeds) {
      await feed.release();
    }
  }

  // ──────────────────────────────────────────────────────────
  // Typing indicators
  // ──────────────────────────────────────────────────────────

  /// Broadcast that we're typing in the open channel (throttled). Called by
  /// the composer on each keystroke.
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingThrottle) {
      return;
    }
    final user = _serverCubit.state.selectedServer?.user;
    final topic = _rtTopic;
    if (user == null || topic == null) return;
    _lastTypingSent = now;
    topic.send(ServerEvent.typing, {'from': user.id, 'name': user.displayName});
  }

  void _onTyping(Map<String, dynamic> payload) {
    if (isClosed) return;
    final from = BroadcastPayload.stringOf(payload, 'from');
    final name = BroadcastPayload.stringOf(payload, 'name');
    final myId = _serverCubit.state.selectedServer?.user?.id;
    if (from == null || name == null || from == myId) return;

    _typingTimers[from]?.cancel();
    _typingTimers[from] = Timer(_typingTimeout, () => _removeTyping(from));
    if (state.typingUsers[from] == name) return;
    emit(state.copyWith(typingUsers: {...state.typingUsers, from: name}));
  }

  void _removeTyping(String userId) {
    _typingTimers.remove(userId)?.cancel();
    if (isClosed || !state.typingUsers.containsKey(userId)) return;
    emit(state.copyWith(typingUsers: {...state.typingUsers}..remove(userId)));
  }

  void _onChangeDoorbell(Map<String, dynamic> payload) {
    if (isClosed || state.status != ChannelChatStatus.ready) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (messageId != null) unawaited(refreshMessage(messageId));
  }

  /// A member changed a reaction. Refresh just the message they named; a ring
  /// without one (an older client) still gets the whole-history fallback.
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
    switch (state.status) {
      // Read-only reads the same way: this doorbell means a *message*, and a
      // webhook's is readable without any key at all. A heal is a different
      // doorbell (`_onKeySweepDoorbell`), and re-opening the whole channel on
      // every message would be a heavy answer to the wrong signal.
      case ChannelChatStatus.ready:
      case ChannelChatStatus.readOnly:
        unawaited(_fetchAfterLatest());
      case ChannelChatStatus.waitingForKey:
      case ChannelChatStatus.healingKey:
        // A member came online and may have healed our keyring entry.
        unawaited(retry());
      default:
        break;
    }
  }
}
