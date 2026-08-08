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
  Map<String, _ServerSub> get _subs;

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
    final sub = _subs[serverId];
    if (sub == null) return;
    unawaited(() async {
      try {
        await sub.client.rpc('mark_all_read');
      } catch (_) {}
    }());
  }

  /// Moves one cursor to whatever is newest right now (`p_last_read_id: 0`).
  void _markRead(
    String serverId, {
    required String scope,
    required String scopeId,
  }) {
    final sub = _subs[serverId];
    if (sub == null) return;
    unawaited(() async {
      try {
        await sub.client.rpc(
          'mark_read',
          params: {
            'p_scope': scope,
            'p_scope_id': scopeId,
            'p_last_read_id': 0,
          },
        );
      } catch (_) {}
    }());
  }
}
