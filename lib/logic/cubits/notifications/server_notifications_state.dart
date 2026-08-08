part of 'server_notifications_cubit.dart';

/// Unread counts across **all** joined servers, derived from each server's
/// `notifications` table (unread = rows with `read_at IS NULL`).
///
/// Channels and server DMs are counted separately because they are badged in
/// different places — a channel tile, a conversation row — but they come from
/// the same rows and the same subscription (migration 015), so a server's total
/// is simply both halves added up.
///
/// One invariant holds everywhere: **a zero count is an absent key**. Nothing
/// stores an empty inner map or a 0, so a server with no unread messages
/// simply isn't in the maps. The `with*`/`cleared*` transforms below are the
/// only way to change them, which is what keeps that true.
@immutable
class NotificationsState {
  /// serverId → (channelId → unread count). Absent keys mean zero.
  final Map<String, Map<String, int>> unreadByServer;

  /// serverId → (peer user id → unread count) for that server's DMs.
  final Map<String, Map<String, int>> dmUnreadByServer;

  const NotificationsState({
    this.unreadByServer = const {},
    this.dmUnreadByServer = const {},
  });

  int unreadForChannel(String serverId, String channelId) =>
      unreadByServer[serverId]?[channelId] ?? 0;

  /// Unread DMs from one peer on one server.
  int unreadForDm(String serverId, String peerId) =>
      dmUnreadByServer[serverId]?[peerId] ?? 0;

  /// Unread DMs across all of a server's conversations — the badge on the
  /// server's "Server DMs" row.
  int dmUnreadForServer(String serverId) => _sum(dmUnreadByServer, serverId);

  /// Everything unread on a server, channels and DMs together — what the rail
  /// chip and "Mark all as read" are about.
  int unreadForServer(String serverId) =>
      _sum(unreadByServer, serverId) + _sum(dmUnreadByServer, serverId);

  /// Total unread across every server except [exceptServerId] (used for the
  /// "activity on another server" hint on the server header).
  int totalUnreadExcept(String? exceptServerId) {
    var total = 0;
    for (final map in [unreadByServer, dmUnreadByServer]) {
      for (final entry in map.entries) {
        if (entry.key == exceptServerId) continue;
        for (final n in entry.value.values) {
          total += n;
        }
      }
    }
    return total;
  }

  /// Replace one server's counts wholesale — what a re-seed produces.
  NotificationsState withServerCounts(
    String serverId, {
    required Map<String, int> channels,
    required Map<String, int> dms,
  }) => NotificationsState(
    unreadByServer: _replaced(unreadByServer, serverId, channels),
    dmUnreadByServer: _replaced(dmUnreadByServer, serverId, dms),
  );

  /// One more unread message in a channel.
  NotificationsState incremented(String serverId, String channelId) => copyWith(
    unreadByServer: _incremented(unreadByServer, serverId, channelId),
  );

  /// One more unread DM from a peer.
  NotificationsState incrementedDm(String serverId, String peerId) => copyWith(
    dmUnreadByServer: _incremented(dmUnreadByServer, serverId, peerId),
  );

  /// A channel was read. Returns `this` unchanged when it had no badge, so
  /// callers can emit unconditionally without churning identical states.
  NotificationsState clearedChannel(String serverId, String channelId) {
    final next = _cleared(unreadByServer, serverId, channelId);
    if (next == null) return this;
    return copyWith(unreadByServer: next);
  }

  /// A conversation was read. Same `this`-when-unchanged contract as
  /// [clearedChannel].
  NotificationsState clearedDm(String serverId, String peerId) {
    final next = _cleared(dmUnreadByServer, serverId, peerId);
    if (next == null) return this;
    return copyWith(dmUnreadByServer: next);
  }

  /// Drop a whole server, e.g. after leaving it.
  NotificationsState clearedServer(String serverId) {
    if (!unreadByServer.containsKey(serverId) &&
        !dmUnreadByServer.containsKey(serverId)) {
      return this;
    }
    return NotificationsState(
      unreadByServer: Map.of(unreadByServer)..remove(serverId),
      dmUnreadByServer: Map.of(dmUnreadByServer)..remove(serverId),
    );
  }

  NotificationsState copyWith({
    Map<String, Map<String, int>>? unreadByServer,
    Map<String, Map<String, int>>? dmUnreadByServer,
  }) => NotificationsState(
    unreadByServer: unreadByServer ?? this.unreadByServer,
    dmUnreadByServer: dmUnreadByServer ?? this.dmUnreadByServer,
  );

  static int _sum(Map<String, Map<String, int>> outer, String serverId) =>
      outer[serverId]?.values.fold<int>(0, (sum, n) => sum + n) ?? 0;

  static Map<String, Map<String, int>> _replaced(
    Map<String, Map<String, int>> outer,
    String serverId,
    Map<String, int> counts,
  ) {
    final next = Map.of(outer);
    if (counts.isEmpty) {
      next.remove(serverId);
    } else {
      next[serverId] = Map.unmodifiable(counts);
    }
    return next;
  }

  static Map<String, Map<String, int>> _incremented(
    Map<String, Map<String, int>> outer,
    String serverId,
    String key,
  ) {
    final inner = Map<String, int>.from(outer[serverId] ?? const {});
    inner[key] = (inner[key] ?? 0) + 1;
    return Map.of(outer)..[serverId] = inner;
  }

  /// The map with one count removed, or null when there was nothing to remove
  /// (so the caller can hand back the same state instance).
  static Map<String, Map<String, int>>? _cleared(
    Map<String, Map<String, int>> outer,
    String serverId,
    String key,
  ) {
    final inner = outer[serverId];
    if (inner == null || !inner.containsKey(key)) return null;
    final updated = Map<String, int>.from(inner)..remove(key);
    final next = Map.of(outer);
    if (updated.isEmpty) {
      next.remove(serverId);
    } else {
      next[serverId] = updated;
    }
    return next;
  }
}
