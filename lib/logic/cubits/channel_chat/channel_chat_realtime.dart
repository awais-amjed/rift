part of 'channel_chat_cubit.dart';

/// The open channel's Realtime topic: who is typing, and the doorbells that
/// say something changed.
///
/// Every ping here is only a doorbell. The database row is what's true, so the
/// receiver always goes and reads it — which is what makes a forged broadcast
/// cost a wasted request and nothing more. None of them carry message text,
/// and none of them are trusted to say what happened.
mixin _ChannelChatRealtimeMixin
    on
        Cubit<ChannelChatState>,
        _ChannelChatHistoryMixin,
        _ChannelChatReactionsMixin {
  /// Re-open the channel — how a member waiting for a key retries once someone
  /// who can heal them comes online.
  Future<void> retry();

  SupabaseClient? _rtClient;
  RealtimeChannel? _rtChannel;

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
    if (server.supabaseKey == null) return;
    _rtClient = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _rtChannel = _rtClient!.channel('chat:$channelId')
      ..onBroadcast(event: 'new_message', callback: (_) => _onDoorbell())
      ..onBroadcast(event: 'message_changed', callback: _onChangeDoorbell)
      ..onBroadcast(event: 'typing', callback: _onTyping)
      ..onBroadcast(event: 'reaction', callback: _onReactionDoorbell)
      ..subscribe();
  }

  Future<void> _teardownRealtime() async {
    final channel = _rtChannel;
    final client = _rtClient;
    _rtChannel = null;
    _rtClient = null;
    _lastTypingSent = null;
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    try {
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
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
    if (user == null || _rtChannel == null) return;
    _lastTypingSent = now;
    try {
      _rtChannel!.sendBroadcastMessage(
        event: 'typing',
        payload: {'from': user.id, 'name': user.displayName},
      );
    } catch (_) {}
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
        // A member came online and may have healed our keyring entry.
        unawaited(retry());
      default:
        break;
    }
  }
}
