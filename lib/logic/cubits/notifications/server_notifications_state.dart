part of 'server_notifications_cubit.dart';

/// Unread counts across **all** joined servers, derived from each server's
/// `notifications` table (unread = rows with `read_at IS NULL`).
///
/// One invariant holds everywhere: **a zero count is an absent key**. Nothing
/// stores an empty channel map or a 0, so a server with no unread messages
/// simply isn't in [unreadByServer]. The `with*`/`cleared*` transforms below
/// are the only way to change the map, which is what keeps that true.
@immutable
class NotificationsState {
  /// serverId → (channelId → unread count). Absent keys mean zero.
  final Map<String, Map<String, int>> unreadByServer;

  const NotificationsState({this.unreadByServer = const {}});

  int unreadForChannel(String serverId, String channelId) =>
      unreadByServer[serverId]?[channelId] ?? 0;

  int unreadForServer(String serverId) =>
      unreadByServer[serverId]?.values.fold<int>(0, (sum, n) => sum + n) ?? 0;

  /// Total unread across every server except [exceptServerId] (used for the
  /// "activity on another server" hint on the server header).
  int totalUnreadExcept(String? exceptServerId) {
    var total = 0;
    for (final entry in unreadByServer.entries) {
      if (entry.key == exceptServerId) continue;
      for (final n in entry.value.values) {
        total += n;
      }
    }
    return total;
  }

  /// Replace one server's counts wholesale — what a re-seed produces.
  NotificationsState withServerCounts(
    String serverId,
    Map<String, int> counts,
  ) => counts.isEmpty
      ? clearedServer(serverId)
      : _withServer(serverId, Map.unmodifiable(counts));

  /// One more unread message in a channel.
  NotificationsState incremented(String serverId, String channelId) {
    final channels = Map<String, int>.from(
      unreadByServer[serverId] ?? const {},
    );
    channels[channelId] = (channels[channelId] ?? 0) + 1;
    return _withServer(serverId, channels);
  }

  /// A channel was read. Returns `this` unchanged when it had no badge, so
  /// callers can emit unconditionally without churning identical states.
  NotificationsState clearedChannel(String serverId, String channelId) {
    final channels = unreadByServer[serverId];
    if (channels == null || !channels.containsKey(channelId)) return this;
    final updated = Map<String, int>.from(channels)..remove(channelId);
    return updated.isEmpty
        ? clearedServer(serverId)
        : _withServer(serverId, updated);
  }

  /// Drop a whole server, e.g. after leaving it.
  NotificationsState clearedServer(String serverId) {
    if (!unreadByServer.containsKey(serverId)) return this;
    final next = Map<String, Map<String, int>>.from(unreadByServer)
      ..remove(serverId);
    return NotificationsState(unreadByServer: next);
  }

  NotificationsState _withServer(String serverId, Map<String, int> channels) {
    final next = Map<String, Map<String, int>>.from(unreadByServer);
    next[serverId] = channels;
    return NotificationsState(unreadByServer: next);
  }

  NotificationsState copyWith({
    Map<String, Map<String, int>>? unreadByServer,
  }) =>
      NotificationsState(unreadByServer: unreadByServer ?? this.unreadByServer);
}
