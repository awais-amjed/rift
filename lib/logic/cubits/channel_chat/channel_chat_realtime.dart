part of 'channel_chat_cubit.dart';

/// The open channel, live: who is typing, and the doorbells that say something
/// changed.
///
/// The doorbells come from the database, on the
/// server's topic for an open channel and on the channel's own for a private
/// one, so a message arrives whoever wrote it and however — a bot writing
/// through the REST API included, which no client-rung doorbell ever covered.
/// They carry ids, never text: the row is what's true, and the receiver always
/// goes and reads it. `chat:<id>` carries only typing, which clients send;
/// `channel:<id>` carries only what the database says.
mixin _ChannelChatRealtimeMixin
    on
        Cubit<ChannelChatState>,
        _ChannelChatHistoryMixin,
        _ChannelChatReactionsMixin,
        _ChannelChatPinsMixin,
        _ChannelChatPollsMixin {
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
    // A private channel's news arrives on its own topic, an
    // open one's on the server's. The caller's own topic is held either way,
    // because an ephemeral reply — a bot answering one person — is addressed
    // to them rather than to the channel.
    final private = server.channels
        .where((channel) => channel.id == channelId)
        .any((channel) => channel.isPrivate);
    for (final topic in [
      if (private)
        ServerTopics.channel(channelId)
      else
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
          _onDoorbell(announced: BroadcastPayload.stringOf(message, 'id'));
        })
        ..onBroadcast(ServerEvent.messageChanged, (message) {
          if (here(message)) _onChangeDoorbell(message);
        })
        ..onBroadcast(ServerEvent.reaction, (message) {
          if (here(message)) _onReactionDoorbell(message);
        })
        ..onBroadcast(ServerEvent.pin, (message) {
          if (here(message)) _onPinDoorbell(message);
        })
        ..onBroadcast(ServerEvent.poll, (message) {
          if (here(message)) _onPollDoorbell(message);
        });
      _rtFeeds.add(feed);
    }

    // What a `/` here turns into is decided from the bots' command lists, read
    // when the channel opened. A bot that publishes a new one says so on the
    // server's topic whatever the channel, private ones included — without
    // hearing it, a verb added since goes out as sealed text the bot cannot
    // read.
    final roster = realtime.join(server, ServerTopics.server(server.id));
    if (roster != null) {
      roster.onBroadcast(ServerEvent.bots, (_) => _onBotsDoorbell(channelId));
      _rtFeeds.add(roster);
    }
  }

  Future<void> _onBotsDoorbell(String channelId) async {
    final bots = await _serverCubit.listBots(channelId: channelId);
    if (isClosed || state.channelId != channelId) return;
    emit(state.copyWith(bots: bots));
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

  /// How long to wait before asking again for a message that was announced
  /// and did not arrive.
  static const _missedRetry = Duration(seconds: 2);

  /// Fetch what is newer, and check that what was announced actually landed.
  ///
  /// The doorbell only says "go and look"; the looking can fail — a request
  /// that times out, a token that expires between the two — and the message
  /// then never appears, because nothing announces it a second time. Once the
  /// id is known that silence is detectable, so it is asked for directly
  /// rather than waiting for somebody to reopen the channel. Seen once, not
  /// reproduced: a message that reached the other client's socket and never
  /// its screen.
  Future<void> _fetchAnnounced(String? announced) async {
    await _fetchAfterLatest();
    if (isClosed || announced == null) return;
    if (state.messages.any((message) => message.id == announced)) return;
    await Future<void>.delayed(_missedRetry);
    if (isClosed) return;
    await fetchMissingMessage(announced);
  }

  /// [announced] is the id the database named, when it named one.
  void _onDoorbell({String? announced}) {
    if (isClosed) return;
    switch (state.status) {
      // Read-only reads the same way: this doorbell means a *message*, and a
      // webhook's is readable without any key at all. A heal is a different
      // doorbell (`_onKeySweepDoorbell`), and re-opening the whole channel on
      // every message would be a heavy answer to the wrong signal.
      case ChannelChatStatus.ready:
      case ChannelChatStatus.readOnly:
        unawaited(_fetchAnnounced(announced));
      case ChannelChatStatus.waitingForKey:
      case ChannelChatStatus.healingKey:
        // A member came online and may have healed our keyring entry.
        unawaited(retry());
      default:
        break;
    }
  }
}
