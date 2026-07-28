part of 'server_notifications_cubit.dart';

/// Unread counts across **all** joined servers, derived from each server's
/// `notifications` table (unread = rows with `read_at IS NULL`).
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

  NotificationsState copyWith({
    Map<String, Map<String, int>>? unreadByServer,
  }) =>
      NotificationsState(unreadByServer: unreadByServer ?? this.unreadByServer);
}
