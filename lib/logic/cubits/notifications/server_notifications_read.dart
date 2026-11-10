part of 'server_notifications_cubit.dart';

/// Clearing badges: the three "this has been read" entry points, and the read
/// cursors behind them.
///
/// A cursor per conversation (`read_state`) rather than a read flag per
/// delivered row. Both are server-side, so read on one device is read on the
/// others, but a cursor is one row written when you actually read something
/// instead of a row per message per recipient written when anyone sends.
///
/// Every one is optimistic-then-best-effort: the local count drops immediately
/// and the write is fire-and-forget, because a badge that waits for a round
/// trip feels broken and a failed write self-heals on the next re-seed. The
/// RPC only ever moves a cursor forward, so a stale client can't un-read what
/// another device already read.
mixin _ReadMarkingMixin on Cubit<NotificationsState> {
  SessionRepository get _session;
  Map<String, _ServerSub> get _subs;
  Future<void> _seed(String serverId);

  /// A re-count waiting to run, per server. "Mark all as read" on another
  /// device can arrive as a few `read` events at once, and a message read as
  /// it lands moves the cursor once per message; one count after they settle
  /// answers all of them.
  final Map<String, Timer> _recounts = {};

  /// When each server was last counted again because the window came back.
  final Map<String, DateTime> _focusRecounts = {};

  static const _recountSettle = Duration(milliseconds: 400);

  /// The least time between two focus re-counts of one server. Focus comes and
  /// goes with every alt-tab, and the `read` event is what keeps a badge
  /// current; this only catches one that was missed, a socket that dropped
  /// while the laptop slept.
  static const _focusRecountEvery = Duration(minutes: 1);

  /// Mark a channel read and clear its badge.
  void markChannelRead(String serverId, String channelId) {
    emit(state.clearedChannel(serverId, channelId));
    _markRead(serverId, scope: 'channel', scopeId: channelId);
  }

  /// The DM equivalent: everything from one peer.
  void markDmRead(String serverId, String peerId) {
    emit(state.clearedDm(serverId, peerId));
    _markRead(serverId, scope: 'dm', scopeId: peerId);
  }

  /// Mark a whole server read, channels and conversations alike.
  void markServerRead(String serverId) {
    emit(state.clearedServer(serverId));
    if (!_subs.containsKey(serverId)) return;
    unawaited(UnreadApi(_session.on(serverId)).markAllRead());
  }

  /// Moves one cursor to whatever is newest right now (`p_last_read_id: 0`).
  void _markRead(
    String serverId, {
    required String scope,
    required String scopeId,
  }) {
    if (!_subs.containsKey(serverId)) return;
    unawaited(
      UnreadApi(_session.on(serverId)).markRead(scope: scope, scopeId: scopeId),
    );
  }

  // ── Read on another device ────────────────────────────────────

  /// One of our devices moved a read cursor on [serverId] (`read`, on our own
  /// topic). The payload names the conversation when one cursor moved, and is
  /// empty when several did. A conversation this device already shows as read
  /// needs nothing — which is also the device that did the reading, since it
  /// hears its own event. Otherwise count again rather than clearing here: a
  /// cursor partway up a conversation leaves some of it unread.
  // Called through the subscriptions mixin's abstract declaration, which the
  // unused-element check can't follow back here.
  // ignore: unused_element
  void _onReadElsewhere(String serverId, Map<String, dynamic> payload) {
    if (isClosed) return;
    final scope = payload['scope'];
    final scopeId = payload['scope_id'];
    final stillUnread = switch ((scope, scopeId)) {
      ('channel', final String id) => state.unreadForChannel(serverId, id) > 0,
      ('dm', final String id) => state.unreadForDm(serverId, id) > 0,
      // Raw counts, not the rail's sum: that one leaves out muted
      // channels, whose counts would then go stale.
      _ =>
        (state.unreadByServer[serverId]?.isNotEmpty ?? false) ||
            (state.dmUnreadByServer[serverId]?.isNotEmpty ?? false),
    };
    if (stillUnread) _recountSoon(serverId);
  }

  /// The window came back: count every server again that has not been counted
  /// for focus within [_focusRecountEvery].
  void _recountOnFocus() {
    final now = DateTime.now();
    for (final serverId in _subs.keys) {
      final last = _focusRecounts[serverId];
      if (last != null && now.difference(last) < _focusRecountEvery) continue;
      _focusRecounts[serverId] = now;
      _recountSoon(serverId);
    }
  }

  void _recountSoon(String serverId) {
    _recounts[serverId]?.cancel();
    _recounts[serverId] = Timer(_recountSettle, () {
      _recounts.remove(serverId);
      if (!isClosed) unawaited(_seed(serverId));
    });
  }

  void _cancelRecounts() {
    for (final timer in _recounts.values) {
      timer.cancel();
    }
    _recounts.clear();
  }
}
