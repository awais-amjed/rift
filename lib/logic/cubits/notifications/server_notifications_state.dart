part of 'server_notifications_cubit.dart';

/// Per-channel unread counts for the currently selected server, derived from the
/// server's `notifications` table (unread = rows with `read_at IS NULL`).
@immutable
class NotificationsState {
  /// channel id → unread count. Absent means zero.
  final Map<String, int> unreadByChannel;

  const NotificationsState({this.unreadByChannel = const {}});

  int unreadFor(String channelId) => unreadByChannel[channelId] ?? 0;

  int get totalUnread =>
      unreadByChannel.values.fold(0, (sum, n) => sum + n);

  NotificationsState copyWith({Map<String, int>? unreadByChannel}) =>
      NotificationsState(
        unreadByChannel: unreadByChannel ?? this.unreadByChannel,
      );
}
