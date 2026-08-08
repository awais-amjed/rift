part of 'server_notifications_cubit.dart';

/// Clearing badges: the three "this has been read" entry points and the one
/// `read_at` write behind them.
///
/// Every one is optimistic-then-best-effort — the local count drops
/// immediately and the RLS UPDATE is fire-and-forget, because a badge that
/// waits for a round trip feels broken and a failed write self-heals on the
/// next re-seed.
mixin _ReadMarkingMixin on Cubit<NotificationsState> {
  Map<String, _ServerSub> get _subs;

  /// Mark every unread notification for a channel read and clear its badge.
  void markChannelRead(String serverId, String channelId) {
    emit(state.clearedChannel(serverId, channelId));
    _markRead(serverId, channelId: channelId);
  }

  /// The DM equivalent: every unread row from one peer.
  void markDmRead(String serverId, String peerId) {
    emit(state.clearedDm(serverId, peerId));
    _markRead(serverId, peerId: peerId);
  }

  /// Mark a whole server read, channels and DMs alike — "Mark all as read".
  ///
  /// No target filter: each server has its own database, so "no filter"
  /// already means "this server only".
  void markServerRead(String serverId) {
    emit(state.clearedServer(serverId));
    _markRead(serverId);
  }

  /// Stamps `read_at` on the caller's unread rows on one server, narrowed to a
  /// channel or a peer when given one.
  void _markRead(String serverId, {String? channelId, String? peerId}) {
    final sub = _subs[serverId];
    if (sub == null) return;
    unawaited(() async {
      try {
        var query = sub.client
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', sub.userId)
            .isFilter('read_at', null);
        if (channelId != null) query = query.eq('channel_id', channelId);
        if (peerId != null) query = query.eq('dm_peer_id', peerId);
        await query;
      } catch (_) {}
    }());
  }
}
